import structs/ArrayList
import ../io/TabbedWriter

import ../frontend/Token
import Expression, Type, Visitor, TypeDecl, Cast, FunctionCall, FunctionDecl,
       Module, Node, VariableDecl, VariableAccess, BinaryOp, Argument,
       Return, CoverDecl, BaseType
import tinker/[Response, Resolver, Trail, Errors]

StructDecl: class extends TypeDecl {

    isAbstract := false
    isFinal := false


    init: func ~classDeclNoSuper(.name, .token) {
        super(name, token)
        if(!isMeta) {
            meta isOutput = false
        }

    }

    init: func ~classDeclNotMeta(.name, .superType, .token) {
        init(name, superType, false, token)
    }

    init: func ~classDecl(.name, .superType, =isMeta, .token) {
        super(name, superType, token)
    }

    isAbstract: func -> Bool { isAbstract }

    byRef?: func -> Bool { false }

    accept: func (visitor: Visitor) { visitor visitStructDecl(this) }

    resolve: func (trail: Trail, res: Resolver) -> Response {

        {
            response := super(trail, res)
            if (!response ok()) return response
        }

        return Response OK
    }

    writeSize: func (w: TabbedWriter, instance: Bool) {
        w app("sizeof("). app(underName()). app(')')
    }

    
    getBaseClass: func ~afterResolve(fDecl: FunctionDecl) -> StructDecl {
        b: Bool
        getBaseClass(fDecl, false, b&)
    }

    getBaseClass: func ~noInterfaces (fDecl: FunctionDecl, comeBack: Bool*) -> StructDecl {
        getBaseClass(fDecl, false, comeBack)
    }

    getBaseClass: func (fDecl: FunctionDecl, withInterfaces: Bool, comeBack: Bool*) -> StructDecl {
        sRef := getSuperRef() as StructDecl
       // first look in the supertype, if any
        if(sRef != null) {
             
            base := sRef getBaseClass(fDecl, comeBack)
            if(base != null) {
               return base
            }
        }

        // if all else fails, try in this
        finalScore := 0
        if(getFunction(fDecl name, fDecl suffix ? fDecl suffix : "", null, false, finalScore&) != null) {

            return this
        }

        return null
    }

    replace: func (oldie, kiddo: Node) -> Bool { false }

/*
    addFunction: func (fDecl: FunctionDecl) {

        "addFunction:" println()
        fDecl toString() println()
        hash := hashName(fDecl)
        old := functions get(hash)
        if (old != null) { // init is an exception
            if(old == fDecl) Exception new(This, "Replacing %s with %s, which is the same!" format (old getName(), fDecl getName())) throw()
            token module params errorHandler onError(FunctionRedefinition new(old, fDecl))
            return
        }

        functions put(hash, fDecl)
        fDecl setOwner(this)

    }
*/
}
