
import os/Coro, structs/[ArrayList, List]

import ../[Node, Module]

Task: class {
    id: Int { get set }
    idSeed := static 0
    
    parentCoro, coro: Coro

    oldStackBase: Pointer
    
    node: Node { get set }
    done?: Bool { get set }

    init: func (=parentCoro, =node) {
        idSeed += 1
        id = idSeed
        coro = Coro new()
        done? = false
        
        (toString() + " created") println()
    }

    start: func {
        (toString() + " started") println()
        stackBase := coro stack
        stackSize := coro allocatedStackSize
        
        // Adjust the stackbottom and add our Coro's stack as a root for the GC
        GC_stackbottom = stackBase
        GC_add_roots   (stackBase, stackBase + stackSize)
        
        parentCoro startCoro(coro, ||
            node resolve(this)
            Exception new("Error! task returned - this shouldn't happened") throw()
        )
    }

    done: func {
        (toString() + " done") println()
        done? = true
        yield()
    }

    yield: func {
        (toString() + " yielding, switching back to parent") println()
        GC_stackbottom = parentCoro stack
        
        coro switchTo(parentCoro)
    }

    queueAll: func (f: Func (Func (Node))) {
        pool := ArrayList<Node> new()
        f(|n| spawn(n, pool))
        exhaust(pool)
    }

    spawn: func (n: Node, pool: List<Task>) {
        (toString() + " spawning for " + n toString())
        task := Task new(coro, n)
        task start()
        if(!task done?) pool add(task)
    }

    exhaust: func (pool: List<Task>) {
        (toString() + " exhausting pool ") println()
        while(!pool empty?()) {
            oldPool := pool
            pool = ArrayList<Task> new()

            oldPool each(|task|
                (toString() + " switching to unfinished task") println()
                switchTo(task)
                if(!task done?) pool add(task)
            )

            yield()
        }
    }

    switchTo: func (task: Task) {
        GC_stackbottom = coro stack
        coro switchTo(task coro)
    }

    toString: func -> String {
        "[#%d %s]" format(id, node toString() toCString())
    }
}

Resolver: class extends Node {

    modules: ArrayList<Module> { get set }

    init: func {
        modules = ArrayList<Module> new()
    }

    start: func {
        "Resolver started, with %d module(s)!" printfln(modules size)

        mainCoro := Coro new()
        mainCoro initializeMainCoro()

        mainTask := Task new(mainCoro, this)
        mainTask start()
        if(mainTask done?) {
            "All done resolving!" println()
        } else {
            "Not everything was resolved!" println()
        }
        "=================================" println()
    }

    resolve: func (task: Task) {
        // TODO: this is basically queueAll, allow a main Task instead
        task queueAll(|queue|
            modules each(|m| queue(m))
        )
        task done()
    }

}
