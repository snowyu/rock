# OOC Rock Compiler Analysis

## My OOC

### String Declaration:

* C String: c""
  A string is a contiguous sequence of characters terminated by and including the first null character (written '\0' and corresponding to the ASCII character NUL).

* Utf-8 CString: uc""

* String: ""
  <String Length>:32bit<Free Size>:32bit<CString>

        StringRec: Struct {
            len: SIZE_T  //
            free: SSIZE_T // -1 means fixed string constant, can not be re-allocated.
            char data[]
        }
        String: StringRec*

* Utf-8 String: u""

### Struct inheritance

* Data inheritance
* Methods
  * only support static(non-virtual) method

### Object

暂时用OOC/Rock的Object布局

    struct _demo__Animal {
        struct _lang_types__Object __super__;
        lang_String__String name;
    };


    struct _demo__AnimalClass {
        struct _lang_types__ClassClass __super__;
        void (*init)(demo__Animal*);
    };


未来:

    struct _demo__Animal {
        //these fields inherited from parent:
        //-----------------------------------
        //struct _lang_types__ClassClass* isa;
        #ifdef _ANONYMOUS_STRUCT
        struct ObjectRec;
        #else
        Class isa;
        #endif
        //inheritance end
        //---------------
        lang_String__String name;
    };


    struct _demo__AnimalClass {
        //these fields inherited from parent:
        //-----------------------------------
        struct _lang_types__ClassClass* parentClass;
        LongInt InstanceSize;
        String className;
        //inheritance end
        //---------------
        struct _lang_types__ClassClass __super__;
        void (*init)(demo__Animal*);
    };


## howto hack

OOC: Grammar in compiler/ooc/nagaqueen/grammar

u need compile greg first: compiler/ooc/greg

modified the grammar: nagaqueen.leg

可以直接使用rock 下的makefile(make grammar)进行，前提是nagaqueen目录必须是在../rock/ 里面
与“rock”目录同级。

如果在创建类型的使用没有指明supertype，那么就被rock视作为class,
class在类型创建的时候(AstBuilder.ooc)都是没有指明supertype的，当遇到onClassExtends,才
setSuperType。

每一个class类型都有两个struct，他们同时被视作为ClassDecl:
* 一个记录字段本身(Object)：这个是主，在类型声明的时候被创建就是它；
* 一个是VMT(meta Class)，在类型创建的时候同时被创建的meta:TypeDecl.ooc). 用isMeta字段来区分
  NonMeta指向(Object)，用于在meta中指示对应的Object ClassDecl.

type是原始类型(BaseType:的作用是直接输出类型名称到C,便于类型转换Cast)总是指明为Class，
instanceType是名字为类名的原始类型(BaseType), instanceType.ref指向Object.

writeMemberFuncPrototypes(ClassDeclWriter): 写该类所有的函数名头.一般写在fw(xxx-fw.h)文件

"This" 是 VariableDecl, 变量类型为BaseType, 变量类型的.ref指向Object.

CoverDecl 的实现也是 Class，所以定义的所有导入都有ClassClass的东东，很烦，要改！

TypeDecl.ooc

<code>
@@ -250,6 +250,8 @@ void nq_onFunctionStatic(void *this);
 void nq_onFunctionInline(void *this);
 void nq_onFunctionFinal(void *this);
 void nq_onFunctionProto(void *this);
+void nq_onFunctionNonVirtual(void *this);
+void nq_onFunctionVirtual(void *this);
 void nq_onFunctionSuper(void *this);
 void nq_onFunctionSuffix(void *this, char *name);
 void nq_onFunctionBody(void *this);
@@ -570,6 +572,8 @@ RegularFunctionDecl =
             (-  ( externName:ExternName  { nq_onFunctionExtern(core->this, externName) }
                 | unmangledName:UnmangledName { nq_onFunctionUnmangled(core->this, unmangledName) }
                 | ABSTRACT_KW { nq_onFunctionAbstract(core->this) }
+                | VIRTUAL_KW  { nq_onFunctionVirtual(core->this) }
+                | NONVIRTUAL_KW { nq_onFunctionNonVirtual(core->this) }
@@ -1426,6 +1430,8 @@ ENUM_KW      = "enum"
 INTERFACE_KW = "interface"
 FROM_KW      = "from"
 ABSTRACT_KW  = "abstract"
+VIRTUAL_KW   = "virtual"
+NONVIRTUAL_KW= "non-virtual"

</code>

then goto compiler/ooc/rock

    make grammar

then u can modified the source to match: 

<code>
+++ b/sdk/lang/types.ooc
@@ -18,6 +18,13 @@ Object: abstract class {
     /// Finalizer: cleans up any objects belonging to this instance
     __destroy__: func {}
 
+    /** free the object manual */
+    free: func {
+      __destroy__()
+      println("freed!")
+      gc_free(this)
+    }
+


+++ b/source/rock/frontend/AstBuilder.ooc
@@ -632,6 +632,14 @@ AstBuilder: class {
         peek(FunctionDecl) isFinal = true
     }
 
+    onFunctionVirtual: unmangled(nq_onFunctionVirtual) func {
+        peek(FunctionDecl) isVirtual = true
+    }
+
+    onFunctionNonVirtual: unmangled(nq_onFunctionNonVirtual) func {
+        peek(FunctionDecl) isVirtual = false
+    }

+++ b/source/rock/backend/cnaughty/ClassDeclWriter.ooc
@@ -86,7 +86,7 @@ ClassDeclWriter: abstract class extends Skeleton {
         // Now write all virtual functions prototypes in the class struct
         for (fDecl in cDecl functions) {
 
-            if(fDecl isExtern()) continue
+            if(!fDecl isVirtual || fDecl isExtern()) continue
 
             if(cDecl getSuperRef() != null) {
                 superDecl : FunctionDecl = null
@@ -139,7 +139,7 @@ ClassDeclWriter: abstract class extends Skeleton {
             if(fDecl isProto()) current app("extern ")
             FunctionDeclWriter writeFuncPrototype(this, fDecl, null)
             current app(';')
-            if(!fDecl isStatic() && !fDecl isAbstract() && !fDecl isFinal()) {
+            if(!fDecl isVirtual() && !fDecl isStatic() && !fDecl isAbstract() && !fDecl isFinal()) {
                 current nl()
                 FunctionDeclWriter writeFuncPrototype(this, fDecl, "_impl")
                 current app(';')
@@ -192,7 +192,7 @@ ClassDeclWriter: abstract class extends Skeleton {
 
         for(fDecl: FunctionDecl in cDecl functions) {
 
-            if (fDecl isStatic() || fDecl isFinal() || fDecl isExternWithName()) {
+            if (!fDecl isVirtual() || fDecl isStatic() || fDecl isFinal() || fDecl isExternWithName()) {
                 continue
             }
 
@@ -225,7 +225,7 @@ ClassDeclWriter: abstract class extends Skeleton {
             }
 
             current nl(). nl()
-            FunctionDeclWriter writeFuncPrototype(this, decl, (decl isFinal()) ? null : "_impl")
+            FunctionDeclWriter writeFuncPrototype(this, decl, (decl isFinal() || !decl isVirtual()) ? null : "_impl")
             current app(' '). openBlock()

+++ b/source/rock/middle/FunctionDecl.ooc
@@ -64,6 +64,7 @@ FunctionDecl: class extends Declaration {
     isFinal := false
     isProto := false
     isSuper := false
+    isVirtual := true
     externName : String = null
     unmangledName: String = null
 
@@ -164,6 +165,7 @@ FunctionDecl: class extends Declaration {
         copy isFinal = isFinal
         copy isProto = isProto
         copy isSuper = isSuper
+        copy isVirtual = isVirtual
         copy externName = externName
         copy unmangledName = unmangledName
 
@@ -213,6 +215,10 @@ FunctionDecl: class extends Declaration {
     isSuper:    func -> Bool { isSuper }
     setSuper:   func (=isSuper) {}
 
+    isVirtual:    func -> Bool { isVirtual }
+    setVirtual:   func (=isVirtual) {}
+
+
     isAnon: func -> Bool { isAnon }
 
     debugCondition: inline func -> Bool {
</code>




## The Object System

sdk必须存在lang目录，并且lang目录下必须存在(参考修改的sdk)：
types.ooc, String.ooc 文件

types.ooc 必须要有Object and Class 的定义。

OOC_LIBS=/Volumes/MacintoshHD/Users/riceball/trac/compiler/ooc/sdk/sdk rock -gc=off --onlygen demo

多个Library 目录在OOC_LIBS中用":"分隔。OOC_LIBS也用于指明sdk path。


* rock/source/rock/
  * frontend: 为 rock 命令行编译器的代码，以及调用各个gcc, tcc, clang等编译器的。
  * backend: rock 的各种语法writer.
  * middle: rock 的各种语法定义.

ok maybe add the non-virtual and virtual keyword to suite more requirements.
and u can add the compiler directive like "default_method_type" to indicate the method type when no method type tag. It should preserve the compability on the default SDK. I do not like DRW(Don't Reinvent the Wheel).

In fact , the dynamic or static spec can be resovled on the SDK totally. I would rather share the same ooc compiler than a diff one.

```OOC
//like c struct, but u can put methods together here and support inheritance.
ObjectStruct: abstract struct {
     class: Class
     __destroy__:  virtual func {}
     __defaults__: virtual func {}
     free: non-virtual func{this __destroy__()}
     new: non-virtual func-> Object* {
         result : Object* = super new()
         result __defaults__
         return result
     }
}

Object:  ObjectStruct*

ClassStruct: abstract struct {
   ....
}

Class: ClassStruct*


```


<pre>
//OOC Source Code:
Object: abstract class {

    class: Class

    /// Instance initializer: set default values for a new instance of this class
    __defaults__: func {}

    /// Finalizer: cleans up any objects belonging to this instance
    __destroy__: func {}

    /** return true if *class* is a subclass of *T*. */
    instanceOf?: final func (T: Class) -> Bool {
        if(!this) return false
        
        current := class
        while(current) {
            if(current == T) return true
            current = current super
        }
        false
    }

}
</pre>

It will be translated into C source:

<code>

//the object record:
struct _lang_types__Object {
    lang_types__Class* class;
};

//the object class record:
struct _lang_types__ObjectClass {
    struct _lang_types__Class __super__;
    void (*__defaults__)(lang_types__Object*);
    void (*__destroy__)(lang_types__Object*);
    lang_types__Bool (*instanceOf__quest)(lang_types__Object*, lang_types__Class*);
    void (*__load__)();
};

</code>

我想要改进，增加 Struct 类型.

<code>
  Struct abstract struct {
  }

  MyStruct: Struct {
      name: String
      init: func() {}
  }

</code>


<code>

struct _lang_types__Struct {}
struct _lang_types__MyStruct {
    String name;
}

void _lang_types__MyStruct_init(lang_types__MyStruct* this);

</code>



