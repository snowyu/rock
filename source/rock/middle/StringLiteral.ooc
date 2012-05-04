import ../frontend/[Token, BuildParams]
import Literal, Visitor, Type, BaseType, VariableDecl, VariableAccess,
        Statement, Module, FunctionDecl
import tinker/[Response, Resolver, Trail, Errors]

StringLiteral: class extends Literal {

    value: String
    raw := false
    objectType := static BaseType new("String", nullToken)
    rawType := static BaseType new("CString", nullToken)

    init: func ~stringLiteral (=value, .token) {
        super(token)
    }

    clone: func -> This { new(value clone(), token) }

    accept: func (visitor: Visitor) { visitor visitStringLiteral(this) }

    getType: func -> Type { raw ? rawType : objectType }

    toString: func -> String { "\"" + value + "\"" }
    
    resolve: func (trail: Trail, res: Resolver) -> Response {

        if(!super(trail, res) ok()) return Response LOOP

        // unwrap object string literals, for optimization
        if (!raw) {
            parent := trail peek()
            if(parent class != VariableDecl) {
                {
                    idx := trail find(FunctionDecl)
                    if(idx == -1) return Response OK
                }
                
                vDecl := VariableDecl new(null, generateTempName("strLit"), this, token)
                vDecl isStatic = true
                vAcc := VariableAccess new(vDecl, token)
                
                trail module() body add(0, vDecl)
                if(!parent replace(this, vAcc)) {
                    res throwError(CouldntReplace new(token, this, vAcc, trail))
                }
            }
        }

        return Response OK

    }

}
