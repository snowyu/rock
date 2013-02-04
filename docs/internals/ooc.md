# 起因

一直在寻找能用于建立C语言的对象（类）复用体系架构的框架或工具，我需要能通过该工具或框架搭建：

* 静态对象(Struct)
* 动态对象(即指针对象，在heap上分配对象内存，需要释放)
* 静态方法绑定
* 虚方法绑定
* constructor and destructor for dynamic object
* 操作符重载

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
