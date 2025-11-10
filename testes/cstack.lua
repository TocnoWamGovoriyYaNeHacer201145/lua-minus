-- $Id: testes/cstack.lua $
-- See Copyright Notice in file lua.h


local tracegc = require"tracegc"

show"testing stack overflow detection"

-- Segmentation faults in these tests probably result from a C-stack
-- overflow. To avoid these errors, you should set a smaller limit for
-- the use of C stack by Lua, by changing the constant 'LUAI_MAXCCALLS'.
-- Alternatively, you can ensure a larger stack for the program.


local function checkerror (msg, f, ...)
  local s, err = pcall(f, ...)
  assert(not s and string.find(err, msg))
end

do  show("testing stack overflow in message handling")
  local count = 0
  local function loop (x, y, z)
    count = count + 1
    return 1 + loop(x, y, z)
  end
  tracegc.stop()    -- __gc should not be called with a full stack
  local res, msg = xpcall(loop, loop)
  tracegc.start()
  assert(msg == "error in error handling")
  show("final count: ", count)
end


-- bug since 2.5 (C-stack overflow in recursion inside pattern matching)
do  show("testing recursion inside pattern matching")
  local function f (size)
    local s = string.rep("a", size)
    local p = string.rep(".?", size)
    return string.match(s, p)
  end
  local m = f(80)
  assert(#m == 80)
  checkerror("too complex", f, 2000)
end


do  show("testing stack-overflow in recursive 'gsub'")
  local count = 0
  local function foo ()
    count = count + 1
    string.gsub("a", ".", foo)
  end
  checkerror("stack overflow", foo)
  show("final count: ", count)

  show("testing stack-overflow in recursive 'gsub' with metatables")
  local count = 0
  local t = setmetatable({}, {__index = foo})
  foo = function ()
    count = count + 1
    string.gsub("a", ".", t)
  end
  checkerror("stack overflow", foo)
  show("final count: ", count)
end


do   -- bug in 5.4.0
  show("testing limits in coroutines inside deep calls")
  local count = 0
  local lim = 1000
  local function stack (n)
    if n > 0 then return stack(n - 1) + 1
    else coroutine.wrap(function ()
           count = count + 1
           stack(lim)
         end)()
    end
  end

  local st, msg = xpcall(stack, function () return "ok" end, lim)
  assert(not st and msg == "ok")
  show("final count: ", count)
end


do    -- bug since 5.4.0
  local count = 0
  show("chain of 'coroutine.close'")
  -- create N coroutines forming a list so that each one, when closed,
  -- closes the previous one. (With a large enough N, previous Lua
  -- versions crash in this test.)
  local coro = false
  for i = 1, 1000 do
    local previous = coro
    coro = coroutine.create(function()
      local cc <close> = setmetatable({}, {__close=function()
        count = count + 1
        if previous then
          assert(coroutine.close(previous))
        end
      end})
      coroutine.yield()   -- leaves 'cc' pending to be closed
    end)
    assert(coroutine.resume(coro))  -- start it and run until it yields
  end
  local st, msg = coroutine.close(coro)
  assert(not st and string.find(msg, "C stack overflow"))
  show("final count: ", count)
end


do
  show("nesting of resuming yielded coroutines")
  local count = 0

  local function body ()
    coroutine.yield()
    local f = coroutine.wrap(body)
    f();  -- start new coroutine (will stop in previous yield)
    count = count + 1
    f()   -- call it recursively
  end

  local f = coroutine.wrap(body)
  f()
  assert(not pcall(f))
  show("final count: ", count)
end


do    -- bug in 5.4.2
  show("nesting coroutines running after recoverable errors")
  local count = 0
  local function foo()
    count = count + 1
    pcall(1)   -- create an error
    -- running now inside 'precover' ("protected recover")
    coroutine.wrap(foo)()   -- call another coroutine
  end
  checkerror("C stack overflow", foo)
  show("final count: ", count)
end


if T then
  show("testing stack recovery")
  local N = 0      -- trace number of calls
  local LIM = -1   -- will store N just before stack overflow

  -- trace stack size; after stack overflow, it should be
  -- the maximum allowed stack size.
  local stack1
  local dummy

  local function err(msg)
    assert(string.find(msg, "stack overflow"))
    local _, stacknow = T.stacklevel()
    assert(stacknow == stack1 + 200)
  end

  -- When LIM==-1, the 'if' is not executed, so this function only
  -- counts and stores the stack limits up to overflow.  Then, LIM
  -- becomes N, and then the 'if' code is run when the stack is
  -- full. Then, there is a stack overflow inside 'xpcall', after which
  -- the stack must have been restored back to its maximum normal size.
  local function f()
    dummy, stack1 = T.stacklevel()
    if N == LIM then
      xpcall(f, err)
      local _, stacknow = T.stacklevel()
      assert(stacknow == stack1)
      return
    end
    N = N + 1
    f()
  end

  local topB, sizeB   -- top and size Before overflow
  local topA, sizeA   -- top and size After overflow
  topB, sizeB = T.stacklevel()
  tracegc.stop()    -- __gc should not be called with a full stack
  xpcall(f, err)
  tracegc.start()
  topA, sizeA = T.stacklevel()
  -- sizes should be comparable
  assert(topA == topB and sizeA < sizeB * 2)
  show(string.format("maximum stack size: %d", stack1))
  LIM = N      -- will stop recursion at maximum level
  N = 0        -- to count again
  tracegc.stop()    -- __gc should not be called with a full stack
  f()
  tracegc.start()
  show"+"
end

show'OK'
