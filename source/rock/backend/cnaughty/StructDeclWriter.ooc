import structs/[List, ArrayList, HashMap]
import ../../middle/[StructDecl, ClassDecl, FunctionDecl, VariableDecl, TypeDecl,
        Type, Node, InterfaceDecl, InterfaceImpl, CoverDecl]
import Skeleton, FunctionDeclWriter, VersionWriter

StructDeclWriter: abstract class extends Skeleton {

    LANG_PREFIX := static const "lang_types__"
    CLASS_NAME := static const This LANG_PREFIX + "Struct"

    write: static func ~_class (this: Skeleton, cDecl: StructDecl) {

        current = hw
        if(cDecl getVersion()) VersionWriter writeStart(this, cDecl getVersion())
        writeObjectStruct(this, cDecl)
        if(cDecl getVersion()) VersionWriter writeEnd(this)

        current = fw
        if(cDecl getVersion()) VersionWriter writeStart(this, cDecl getVersion())
        writeMemberFuncPrototypes(this, cDecl meta)
        if(cDecl getVersion()) VersionWriter writeEnd(this)

        current = cw
        if(cDecl getVersion()) VersionWriter writeStart(this, cDecl getVersion())
        writeInstanceImplFuncs(this, cDecl meta)
        writeStaticFuncs(this, cDecl meta)
        if(cDecl getVersion()) VersionWriter writeEnd(this)

    }

    writeObjectStruct: static func (this: Skeleton, cDecl: StructDecl) {

        current nl(). app("struct _"). app(cDecl underName()). app(' '). openBlock()

        if (cDecl getSuperRef() != null && cDecl getSuperRef() name != "Object") {
            current nl(). app("struct _"). app(cDecl getSuperRef() underName()). app(" __super__;")
        }

        for(vDecl in cDecl variables) {
            // ignore extern and virtual variables (usually properties)
            if(vDecl isExtern() || vDecl isVirtual()) continue;

            current nl()
            vDecl getType() write(current, vDecl getFullName())
            current app(';')
        }

        current closeBlock(). app(';'). nl(). nl()

    }

    /** Write a function declaration's pointer */
    writeFunctionDeclPointer: static func (this: Skeleton, fDecl: FunctionDecl, doName: Bool) {

        current app((fDecl hasReturn() ? fDecl getReturnType() : voidType) as Node)

        current app(" (*")
        if(doName) FunctionDeclWriter writeSuffixedName(this, fDecl)
        current app(")")

        FunctionDeclWriter writeFuncArgs(this, fDecl, ArgsWriteModes TYPES_ONLY, null);

    }

    /** Write the prototypes of member functions */
    writeMemberFuncPrototypes: static func (this: Skeleton, cDecl: TypeDecl) {
        //writeClassGettingPrototype(this, cDecl)

        for(fDecl: FunctionDecl in cDecl functions) {
            if (!fDecl isOutput) continue
            if(fDecl isExtern()) {
                // write the #define
                FunctionDeclWriter write(this, fDecl)
            }

            if(fDecl isExternWithName() && !fDecl isProto()) {
                continue
            }

            current nl()
            if(fDecl isProto()) current app("extern ")
            FunctionDeclWriter writeFuncPrototype(this, fDecl, null)
            current app(';')

        }

    }

    writeStaticFuncs: static func (this: Skeleton, cDecl: TypeDecl) {

        for (decl: FunctionDecl in cDecl functions) {

            if (!decl isOutput || !decl isStatic() || decl isProto() || decl isAbstract()) continue

            if(decl isExternWithName()) {
                FunctionDeclWriter write(this, decl)
                continue
            }

            current = cw
            current nl()
            FunctionDeclWriter writeFuncPrototype(this, decl);

            current app(' '). openBlock(). nl()

            for(stat in decl body) {
                writeLine(stat)
            }
            current closeBlock()

        }
    }

    writeInstanceImplFuncs: static func (this: Skeleton, cDecl: TypeDecl) {

        // Non-static (ie  instance) functions
        for (decl: FunctionDecl in cDecl functions) {
            if (!decl isOutput || decl isStatic() || decl isAbstract() || decl isExternWithName()) {
                continue
            }

            current nl(). nl()
            FunctionDeclWriter writeFuncPrototype(this, decl, null)
            current app(' '). openBlock()
            
            for(stat in decl body) {
                writeLine(stat)
            }
            current closeBlock()
        }

    }

    getClassType: static func (cDecl: StructDecl) -> StructDecl {
        if(cDecl getNonMeta() != null && cDecl getNonMeta() instanceOf?(InterfaceImpl)){
            cDecl getSuperRef() as StructDecl
        } else {
            cDecl
        }
    }


    writeStructTypedef: static func (this: Skeleton, cDecl: StructDecl) {

        structName := cDecl underName()
        if(cDecl getVersion()) VersionWriter writeStart(this, cDecl getVersion())
        current nl(). app("//writeStructTypedef")
        current nl(). app("struct _"). app(structName). app(";")
        current nl(). app("typedef struct _"). app(structName). app(" "). app(structName). app(";")
        if(cDecl getVersion()) VersionWriter writeEnd(this)

    }

}
