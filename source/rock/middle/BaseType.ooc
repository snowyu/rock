import structs/[List, ArrayList]

import ../backend/cnaughty/AwesomeWriter, ../frontend/[BuildParams, Token]
import tinker/[Response, Resolver, Trail, Errors]

import Type, Declaration, VariableAccess, VariableDecl, TypeDecl,
       InterfaceDecl, Node, StructDecl, ClassDecl, CoverDecl, Cast, FuncType,
       FunctionCall, Module, NamespaceDecl

NumericState: enum {
    UNKNOWN, YES, NO
}

BaseType: class extends Type {

    namespace: VariableAccess = null
    ref: Declaration = null
    name: String
    _numeric : NumericState = NumericState UNKNOWN

    void? : Bool {
        get { super() || name == "void" || name == "Void" }
    }

    typeArgs: List<VariableAccess> = null

    init: func ~baseType (=name, .token) {
        super(token)
    }

    init: func ~withNamespace (=name, =namespace, .token) {
        super(token)
    }

    pointerLevel: func -> Int { 0 }

    isPointer: func -> Bool { name == "Pointer" }

    write: func (w: AwesomeWriter, name: String) {
        if(getRef() == null) {
            Exception new(This, "Trying to write unresolved type " + toString()) throw()
        }
        match {
            case getRef() instanceOf?(InterfaceDecl)=> writeInterfaceType(w, getRef() as InterfaceDecl)
            case getRef() instanceOf?(TypeDecl)     => writeRegularType  (w, getRef() as TypeDecl)
            case getRef() instanceOf?(VariableDecl) => writeGenericType  (w, getRef() as VariableDecl)
        }
        if(name != null) w app(' '). app(name)
    }

    writeInterfaceType: func (w: AwesomeWriter, id: InterfaceDecl) {
        w app(id getFatType() getInstanceType())
    }

    writeRegularType: func (w: AwesomeWriter, td: TypeDecl) {

        if(td isExtern()) {
            if(td instanceOf?(CoverDecl)) {
                cDecl := getRef() as CoverDecl
                fromType := cDecl getFromType()
                if(fromType != null && cDecl isExtern()) {
                    // for extern covers, write directly the underlying
                    // type - since we don't even write a typedef.
                    w app(fromType getGroundType() toString())
                    return
                }
            }

            // still have a chance to have an extern name
            w app(td getExternName())
            return
        }

        while(td instanceOf?(CoverDecl) && td as CoverDecl isAddon()) {
            td = td as CoverDecl getBase() getNonMeta()
        }

        w app(td underName())
        if(td instanceOf?(ClassDecl) || td instanceOf?(StructDecl)) {
            w app('*')
        }
    }

    writeGenericType: func (w: AwesomeWriter, vd: VariableDecl) {
        w app("uint8_t*")
    }

    equals?: func (other: This) -> Bool {
        if(other class != this class) return false
        return (other as BaseType name equals?(name))
    }

    addTypeArg: func (typeArg: VariableAccess) -> Bool {
        if(!typeArgs) typeArgs = ArrayList<VariableAccess> new()
        typeArgs add(typeArg); true
    }

    getName: func -> String { name }

    suggest: func (decl: Declaration) -> Bool {

        if(decl instanceOf?(TypeDecl) && decl as TypeDecl isAddon()) {
            // The second rule of resolve club is: you do *NOT* resolve to an addon.
            // Always resolve to the base instead.
            return suggest(decl as TypeDecl getBase() getNonMeta())
        }
        ref = decl

        if(name == "This" && getRef() instanceOf?(TypeDecl)) {
            tDecl := getRef() as TypeDecl
            name = tDecl getName()
        }
        return true
    }

    resolve: func (trail: Trail, res: Resolver) -> Response {

        if(isResolved()) {
            if(ref token module && ref token module dead) {
                "%s outdated from module %s, re-resolving!" printfln(name, ref token module fullName)
                ref = null
                res wholeAgain(this, "re-resolved because of dead module")
            } else {
                return Response OK
            }
        }

        if(namespace) {

            trail push(this)
            response := namespace resolve(trail, res)
            trail pop(this)
            if(!response ok()) {
                if(res params veryVerbose) "Failed to resolve expr %s of type %s, looping" printfln(namespace toString(), toString())
                return response
            }

            if(namespace getRef() != null && namespace getRef() instanceOf?(NamespaceDecl)) {
                namespace getRef() as NamespaceDecl resolveType(this, res, trail)
            } else {
                res throwError(InvalidNamespaceAccess new(token, this, "Trying to access a type from %s, which is not a namespace" format(namespace toString())))
            }
        }

        if(!ref) {
            depth := trail getSize() - 1
            while(depth >= 0) {
                node := trail get(depth, Node)
                node resolveType(this, res, trail)
                if(ref) {
                    break // break on first match
                }
                depth -= 1
            }
        }

        if(!ref) {
            if(res fatal) {
                if(res params veryVerbose) {
                    trail toString() println()
                }

                msg := "Undefined type '%s'" format(getName())
                similar := findSimilar(res)
                if(similar) msg += similar
                res throwError(UnresolvedType new(token, this, msg))
            }
            if(res params veryVerbose) {
                "     - type %s still not resolved, looping (ref = %p)" printfln(name, getRef())
            }
            return Response LOOP
        } else if(ref instanceOf?(TypeDecl)) {
            tDecl := ref as TypeDecl
            if(!tDecl isMeta && !tDecl getTypeArgs() empty?()) {
                if((typeArgs == null || typeArgs getSize() != tDecl getTypeArgs() getSize()) && !trail peek() instanceOf?(Cast)) {
                    message : String = match {
                        case typeArgs == null =>
                            "No"
                        case typeArgs getSize() < tDecl getTypeArgs() getSize() =>
                            "Too few"
                        case =>
                            "Too many"
                    }

                    res throwError(MismatchedTypeParams new(token, "%s type parameters for %s. It should match %s" format(message, toString(), tDecl getInstanceType() toString())))
                }
            }
        }

        if(typeArgs) {
            trail push(this)
            for(typeArg in typeArgs) {
                response := typeArg resolve(trail, res)
                if(!response ok()) {
                    trail pop(this)
                    return response
                }
            }
            trail pop(this)
        }

        return Response OK

    }

    findSimilar: func (res: Resolver) -> String {

        buff := Buffer new()

        for(imp in res collectAllImports()) {
            module := imp getModule()

            type := module getTypes() get(name)
            if(type) {
                buff append(" (Hint: there's such a type in "). append(imp getPath()). append(")")
            }
        }

        buff toString()

    }

    isResolved: func -> Bool {
        if(ref == null) return false
        if(ref token module && ref token module dead) return false
        if(typeArgs == null) return true
        for(typeArg in typeArgs) if(!typeArg isResolved()) {
            return false
        }
        return true
    }

    getRef: func -> Declaration { ref }
    setRef: func (=ref) {}

    getTypeArgs: func -> List<VariableAccess> { typeArgs }

    getScoreImpl: func (other: Type, scoreSeed: Int) -> Int {
        //printf("%s vs %s, other isGeneric ? %s pointerLevel ? %d isPointer() ? %d, other isPointer() ? %d\n", toString(), other toString(), other isGeneric() toString(), other pointerLevel(), isPointer(), other getGroundType() isPointer())

        if(void?) return This NOLUCK_SCORE

        ourRef := getRef()
        if(!ourRef) return -1
        
        hisRef := other getRef()
        if(!hisRef) return -1

        if(other isGeneric() && other pointerLevel() == 0) {
            // every type is always a match against a flat generic type
            return scoreSeed
        }

        if(isGeneric() && other isPointer()) {
            // a generic value is a match for a pointer
            return scoreSeed / 2
        }

        if(isPointer() && (hisRef instanceOf?(ClassDecl) || hisRef instanceOf?(StructDecl))) {
            // objects are references in ooc
            return scoreSeed / 4
        }

        if((ourRef instanceOf?(ClassDecl) || ourRef instanceOf?(StructDecl)) && other isPointer()) {
            // objects are still references in ooc
            return scoreSeed / 4
        }

        ground := other getGroundType()
        if(isPointer() && (ground isPointer() || ground pointerLevel() > 0)) {
            // two pointers = okay
            return scoreSeed / 2
        }
        
        if(other instanceOf?(BaseType)) {
            if(ourRef == hisRef) {
                // perfect match
                return scoreSeed
            }

            // if we are one of his addons, we're good
            if(hisRef instanceOf?(TypeDecl)) {
                for(addon in hisRef as TypeDecl getAddons()) {
                    hisRef2 := addon base
                    //printf("Reviewing addon %s, ref %s (%s), vs %s (%s)\n", addon getNonMeta() toString(), ourRef toString(), ourRef token toString(), hisRef toString(), hisRef token toString())
                    if(ourRef == hisRef2) {
                        // perfect match
                        return scoreSeed
                    }
                }
            }

            if(ourRef instanceOf?(TypeDecl) && hisRef instanceOf?(TypeDecl)) {
                inheritsScore := ourRef as TypeDecl inheritsScore(hisRef as TypeDecl, scoreSeed - 2)

                // something needs resolving
                if(inheritsScore == -1) {
                    return -1
                }

                bothCovers := ourRef instanceOf?(CoverDecl) && hisRef instanceOf?(CoverDecl)
                if(inheritsScore <= 0 && bothCovers) {
                    // well, try the other way around - covers are lax - but it'll be weaker this time
                    inheritsScore = hisRef as TypeDecl inheritsScore(ourRef as TypeDecl, scoreSeed / 2)
                }

                // cool, a match =)
                if(inheritsScore > 0) {
                    return inheritsScore
                }
            }

            if(isNumericType() && other isNumericType()) {
                // a mild match - it's not too good to mix integer types. Maybe we need more safety here?
                return scoreSeed / 4
            }
        }

        return This NOLUCK_SCORE // no luck.
    }

    _computeNumeric: func {
        // FIXME: that's quite ugly - and what about custom types?
        if ((
           name == "Int"   || name == "UInt"  || name == "Short" ||
           name == "UShort"|| name == "Long"  || name == "ULong" ||
           name == "LLong" || name == "ULLong"|| name == "Int8"  ||
           name == "Int16" || name == "Int32" || name == "Int64" ||
           name == "UInt8" || name == "UInt16"|| name == "UInt32"||
           name == "UInt64"|| name == "SizeT" || name == "Float" ||
           name == "Double"|| name == "SSizeT"|| name == "Octet" )) {
            _numeric = NumericState YES
            return
        }

        down := dig()
        if(down && down isNumericType()) {
            _numeric = NumericState YES
            return
        }

        _numeric = NumericState NO
    }

    isNumericType: func -> Bool {
        if(_numeric == NumericState UNKNOWN) _computeNumeric()
        (_numeric == NumericState YES)
    }

    dereference: func -> Type {
        digged := dig()
        if(digged) {
            return digged dereference()
        }
        null
    }

    clone: func -> This {
        copy := new(name, token)
        if(getTypeArgs()) for(typeArg in getTypeArgs()) {
            copy addTypeArg(typeArg)
        }
        copy setRef(getRef())
        copy
    }

    dig: func -> Type {
        if(getRef() != null && getRef() instanceOf?(CoverDecl)) {
            return ref as CoverDecl getFromType()
        }
        return null
    }

    checkedDigImpl: func (list: List<Type>, res: Resolver) {
        if(getRef() == null) {
            res wholeAgain(this, "Null ref while check-digging")
            return
        }

        list add(this)

        if(getRef() != null && getRef() instanceOf?(CoverDecl)) {
            next := ref as CoverDecl getFromType()
            if(next != null) {
                if(list contains?(next)) {
                    buff := Buffer new()
                    isFirst := true
                    for(t in list) {
                        if(!isFirst) buff append(" -> ")
                        buff append(t toString())
                        isFirst = false
                    }
                    res throwError(CoverDeclLoop new(list first() token, "Loop in cover declaration: %s -> %s -> ..." format(buff toString(), next toString(), list getSize())))
                }
                next checkedDigImpl(list, res)
            }
        }
    }

    inheritsFrom?: func (t: Type) -> Bool {
        if(!t instanceOf?(BaseType)) return false
        bt := t as BaseType
        if(   ref == null || !   ref instanceOf?(TypeDecl)) return false
        if(bt ref == null || !bt ref instanceOf?(TypeDecl)) return false

        return ref as TypeDecl inheritsFrom?(bt ref as TypeDecl)
    }

    replace: func (oldie, kiddo: Node) -> Bool {
        if(typeArgs) return typeArgs replace(oldie as VariableAccess, kiddo as VariableAccess)
        false
    }

    toString: func -> String {
        if(typeArgs == null) return getName()

        sb := Buffer new()
        sb append(getName())
        sb append("<")
        isFirst := true
        if(typeArgs) for(typeArg in typeArgs) {
            if(isFirst) isFirst = false
            else        sb append(", ")
            sb append(typeArg toString())
        }
        sb append(">")
        return sb toString()
    }

    searchTypeArg: func (typeArgName: String, finalScore: Int@) -> Type {
        if(getRef() == null) {
            finalScore = -1
            return null
        }

        if(!getRef() instanceOf?(TypeDecl)) {
            // only TypeDecl have typeArgs anyway.
            return null
        }

        typeRef := getRef() as TypeDecl
        if(typeRef typeArgs == null) return null

        j := 0
        for(arg in typeRef typeArgs) {
            if(arg getName() == typeArgName) {
                //printf("Looking for %s in %s (ref %s), candidate = %s, j = %d, typeArgs size() = %d\n", typeArgName, toString(), typeRef toString(), arg getName(), j, typeArgs ? typeArgs size() : -1)
                if(typeArgs == null || typeArgs getSize() <= j) {
                    continue
                }
                candidate := typeArgs get(j)
                ref := candidate getRef()
                if(ref == null) return null
                result : Type = null

                //printf("Found candidate %s (which is a %s) for typeArg %s, ref is a %s, = %s\n", candidate toString(), candidate class name, typeArgName, ref class name, ref toString())
                if(ref instanceOf?(TypeDecl)) {
                    // resolves to a known type
                    result = ref as TypeDecl getInstanceType()
                } else if(ref instanceOf?(VariableDecl)) {
                    // resolves to an access to another generic type
                    result = BaseType new(ref as VariableDecl getName(), token)
                    result setRef(ref) // FIXME: that is experimental. is that a good idea?
                } else if(ref instanceOf?(FuncType)) {
                    //printf("ref of %s is a %s!\n", candidate toString(), ref class name)
                    result = ref as FuncType
                }
                return result
            }
            j += 1
        }

        // FIXME: debug

        // translate things like:
        // HashMap<K, V> extends Iterator<V>
        current := typeRef
        while(current != null && current getSuperType() != null) {
            result := searchInheritance(typeArgName, current, current getSuperType(), finalScore&)
            if(finalScore == -1) return null
            if(result) return result
            current = current getSuperRef()
        }

        for(interfaceType in typeRef interfaceTypes) {
            result := searchInheritance(typeArgName, typeRef, interfaceType, finalScore&)
            if(finalScore == -1) return null
            if(result) return result
        }

        superType := typeRef getSuperType()
        if(superType != null) {
            //printf("Searching for <%s> in super-type %s\n", typeArgName, superType toString())
            return superType searchTypeArg(typeArgName, finalScore&)
        }

        return null
    }

    searchInheritance: func (typeArgName: String, current: TypeDecl, superType: Type, finalScore: Int@) -> Type {

        j := 0
        superRef := superType getRef() as TypeDecl
        if(superRef == null) {
            finalScore = -1
            return null // something needs to be resolved further
        }

        superArgs := superRef getTypeArgs()
        for(superArg in superArgs) {
            if(superArg getName() == typeArgName) {
                superRealArgs := superType getTypeArgs()
                if(superRealArgs == null || superRealArgs getSize() < j) {
                    continue
                }
                candidate := superRealArgs get(j)

                ref := candidate getRef()

                if(ref == null) {
                    finalScore = -1
                    return null
                }
                result : Type = null

                if(ref instanceOf?(TypeDecl)) {
                    // resolves to a known type
                    result = ref as TypeDecl getInstanceType()
                } else if(ref instanceOf?(VariableDecl)) {
                    // resolves to an access to another generic type
                    result = BaseType new(ref as VariableDecl getName(), token)
                    result setRef(ref) // FIXME: that is experimental. is that a good idea?
                }
                return result
            }
            j += 1
        }

        null
    }

    realTypize: func (call: FunctionCall) -> Type {
        finalScore := 0
        solved := call resolveTypeArg(name, null, finalScore&)
        if(solved) return solved
        this
    }

    setNamespace: func (=namespace) {}

}

UnresolvedType: class extends Error {
    type: Type

    init: func (.token, =type, .message) {
        super(token, message)
    }
}

MismatchedTypeParams: class extends Error {
    init: super func ~tokenMessage
}

InvalidNamespaceAccess: class extends Error {
    type: Type

    init: func (.token, =type, .message) {
        super(token, message)
    }
}

