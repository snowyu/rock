# 起因

一直以来都不是很喜欢C++的繁琐和臃肿, 反而喜欢C的紧凑简单的，以及能在C中掌控一切的感觉。
但是当你要用C来复用数据和方法，即面向对象的时候，写起来就未免感到繁琐和重复:

    typedef struct _Point {
        int x, y;
    } Point;
    typedef struct {
        #ifdef _ANONYMOUS_STRUCT
        struct _Point;
        #else
        int x, y;
        #endif
        int xEnd, yEnd;
    } Line;
    void Point_New(Point *this, int x, int y);
    void Point_DrawTo(Point *this, Canvas *aCanvas);
    void Line_New(Point *this, int x, int y, int xEnd, int yEnd);
    void Line_DrawTo(Point *this, Canvas *aCanvas);

这样写着，真蛋疼，如果能类似这样OO的写法就轻松多了:

    Point: Struct {
        int x,y;
        void New(int x, int y);
        void DrawTo(Canvas *aCanvas);
    }
    Line: Struct extends Point {
        int endX, endY;
        void New(int x, int y, int endX, int endY);
        void DrawTo(Canvas *aCanvas);
    }

还有字符串的处理，在C中也是非常麻烦，因为C没有内置字符串处理方式，所以写起来极为不简便。
当然也可以说你完全把控着字符串处理的实现。这主要得怪C不支持操作符的重载。

    s = str_new();
    s = str_cat(s, "hi");
    s = str_cat(s, "world");
    str_free(s);

如果能这样多好：

    s = "hi" + "world";

在互联网上搜索下来，不甚理想，Object-C的对象模型太复杂，另外其它面向对象C的实现方式大多
采用宏定义，看上去就别扭。最后找到了[OOC-Lang](http://ooc-lang.org)，看上去不错，一种面
向对象的语言（带垃圾回收机制的），编译结果目标代码为c99标准的纯C语言代码。看看了，幸好，
垃圾回收(gc)功能可以禁止掉。支持操作符重载，字符串管理，等等，我要的，不要的都在里面了。

写个简单hello world测试：

    //file: hello.ooc
    main: func{
        "hi world." println()
    }

编译直接产生执行文件看看:

    $rock hello.ooc
    $ls -h
    -rwxr-xr-x   1 riceball  staff   503K Feb 28 20:16 hello
    -rw-r--r--   1 riceball  staff    89B Feb 28 20:11 hello.ooc

发现可执行文件大小为503K，这还算是C么？使用禁止gc开关后，依然还有325K。尽管知道使用面向对象
会对体积和性能有所影响，但是这个差距也忒大了。

    $rock --gc=off hello.ooc
    $ls -h
    -rwxr-xr-x   1 riceball  staff   325K Feb 28 20:16 hello
    -rw-r--r--   1 riceball  staff    89B Feb 28 20:11 hello.ooc

看看它产生的C语言代码到底是怎么回事？

<code>
static lang_String__String* __strLit1;
void olddemo_load() {
    static bool __done__ = false;
    if (!__done__){
        __done__ = true;
        lang_Abstractions_load();
        lang_Buffer_load();
        lang_BufferIterator_load();
        lang_Character_load();
        lang_Exception_load();
        lang_Format_load();
        lang_IO_load();
        lang_Iterators_load();
        lang_Memory_load();
        lang_Numbers_load();
        lang_String_load();
        lang_System_load();
        lang_types_load();
        lang_VarArgs_load();
        __strLit1 = (void*) lang_String__makeStringLiteral("hi world.", 9);
    }
}


lang_Numbers__Int main() {
    olddemo_load();
    lang_String__String_println(__strLit1);
    return 0;
}
</code>

原来OOC-Lang是统一在运行时期进行的初始化加载工作。这使得C编译器无法优化，
只得将所有涉及到的代码全部编入到可执行文件中。这一偷懒不要紧，体积就增加了
几十倍，在互联网上搜了一圈下来，除了它，还真灭有看到更合适了，只有再继续看
看OOC-lang编译器的源代码看能不能改改，浏览下来，发现还算好改。接着看下去，
发现在OOC中对象所有的方法全部都是虚方法，包括Final（这个Final概念来自Java）
方法，都在虚方法表中，没有真正意义上的非虚方法(static关键字在OOC中为类方法)，
不注明任何关键字的方法，默认就是虚方法。给作者提了个issue，作者回答说，OOC正
在逐步发展为越来越动态的语言，因此，OOC会越来越依赖于动态特性，而静态和性能，
不是OOC考虑的，这也许会导致难以阅读或者书写(这个结论太离谱)，作者建议我用C++，
我只得巨汗。发展动态特性，这没错，可是这应该逐步逐层添砖添瓦发展而来。适当分层
非常重要，这样，不同目的开发者都可以各取所需。

这是迫使我开分支，从OOC分离出去啊。作为一个有节操的有懒有蠢的人，
最喜欢的是KISS(KeepItSimply,Stupid)，最讨厌就是重复发明轮子(DRW)了。语言这个
东西，单干是很累的。


产生的C语言利用宏定义和名称前缀的形式来避免重名，看上去总觉得不顺眼，不过为了避免
在大项目中名称冲突，这算是一种解决方案，该想一种更漂亮的方案。

<code>
//come from memory-fwd.h
#define lang_memory__zcalloc zcalloc
lang_types__Pointer lang_memory__gc_malloc(lang_Numbers__SizeT size);
...

//come from memory.h
#ifdef OOC_FROM_C
#define zcalloc(size) (void*) lang_memory__zcalloc((size))
#define gc_malloc(size) (void*) lang_memory__gc_malloc((size))
#define gc_malloc(size) (void*) lang_memory__gc_malloc((size))
#define gc_malloc_atomic(size) (void*) lang_memory__gc_malloc_atomic((size))
#define gc_malloc_atomic(size) (void*) lang_memory__gc_malloc_atomic((size))
....
</code>

烦于每次都要在C语言中输入同样的模式。

一直在寻找能用于建立C语言的对象（类）复用体系架构的框架或工具，我需要能通过该工具或框架搭建：





* OO
  * Struct对象
  * Object对象
  * 静态方法绑定
  * 虚方法绑定
  * constructor and destructor for dynamic object
* 操作符重载
* 字符串管理
* 函数Overload: The same func name but parameters diff.
* 函数参数默认值支持


<pre>
typedef struct {
   int x;
   int y;
} Point;

Point a;  //Static Object
Point *b; //Dynamic Object

void point_draw(Point* this) {}
</pre>


# OOC-Language

    OOC_LIBS=/ooc/sdk/rtl rock -gc=off --driver=make --cstrings demo

原有词汇语义尽量和C保持一致，比如: static, inline 的概念（需要修改OOC）.
所以最终这个东西就不是OOC-lang了，而是iC-Lang


修改OOC

目前没有区分 struct && struct*
所有struct都认为是pointer。

    OOC=bin/c_rock ROCK_DIST=. make self

+ use the c file if exists when include local head file
  * see the Module.ooc(\_collectDeps func), Driver.ooc(copyLocalHeaders func)
  * the SequenceDriver.ooc(collectDeps func) modified too but not work on(Macos, ralib things)!

<code>
//the local include zmalloc.h
include ./zmalloc

if the zmalloc.c file in the same dir
</code>

注意，首先SequenceDriver 和make使用的不是同一种方式进行编译的。

在Sequence中包含的 .h文件被放在 .libs/sdk下，自己模块产生的.h文件被放在
对应的 ./lib/sdk/sdk/目录下(多一个sdk感觉怪怪的)。
.c文件被放在 rock_tmp 目录下的对应目录
.o文件放在 rock_tmp 根目录下。

也许可以把.h文件改成也是放在对应目录下

<code>
  .libs/sdk/zmalloc.h
  .libs/sdk/sdk/lang/Memory-fwd.h
  .libs/sdk/sdk/lang/Memory.h
  rock_tmp/sdk/lang/zmalloc.c
  rock_tmp/lang_zmalloc.o

  #changed to:
  .libs/sdk/lang/zmalloc.h
  .libs/sdk/lang/Memory-fwd.h
  .libs/sdk/lang/Memory.h
  rock_tmp/sdk/lang/zmalloc.c
  rock_tmp/lang_zmalloc.o

</code>

h还有就是Module应该从Include上派生。

另外使用SequenceDriver 编译包含.c的方式报错：

<code>
/usr/bin/ranlib: file: .libs/rtl-osx.a(lang_Numbers.o) has no symbols
/usr/bin/ranlib: file: .libs/rtl-osx.a(lang_zmalloc.o) has no symbols

Undefined symbols for architecture x86_64:
  "_zcalloc", referenced from:
      _lang_memory__gc_malloc in rtl-osx.a(lang_memory.o)
      _lang_memory__gc_calloc in rtl-osx.a(lang_memory.o)
ld: symbol(s) not found for architecture x86_64
</code>

<pre>
Struct: abstract struct {
    new: class func() -> Pointer {
        result := calloc(sizeOf(this)) as this
        return result
    }
    free: func() {
        free(this)
    }
}

Object: abstract struct {
    init: virtual func() {}
    new: class func() -> Pointer {
        result := calloc(sizeOf(this)) as this
        if (result init) result init()
        return result
    }
    destroy: virtual func() {}
    free: func() {
        if (this destroy) this destroy()
        free(this)
    }
}

Point: struct {
    x: Int
    y: Int
    draw: func {}
}

Line: struct extends Point {
    endX: Int
    endY: Int
    draw: func ~withLine {}
}

aLine := Line new()
</pre>


[Object-oriented design patterns in the kernel, part 1]:http://lwn.net/Articles/444910/
[Object-oriented design patterns in the kernel, part 2]:http://lwn.net/Articles/446317/
