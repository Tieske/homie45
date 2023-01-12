#!/usr/bin/env lua

--- CLI application.
-- Description goes here.
-- @script homie45
-- @usage
-- # start the application from a shell
-- homie45 --some --options=here

print("Welcome to the homie45 CLI, echoing arguments:")
for i, val in ipairs(arg) do
  print(i .. ":", val)
end
