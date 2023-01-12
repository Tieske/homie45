local package_name = "homie45"
local package_version = "scm"
local rockspec_revision = "1"
local github_account_name = "Tieske"
local github_repo_name = "homie45"


package = package_name
version = package_version.."-"..rockspec_revision

source = {
  url = "git+https://github.com/"..github_account_name.."/"..github_repo_name..".git",
  branch = (package_version == "scm") and "main" or nil,
  tag = (package_version ~= "scm") and package_version or nil,
}

description = {
  summary = "Homie bridge for Homie 4 devices to Homie 5",
  detailed = [[
    Homie bridge for Homie 4 devices to Homie 5
  ]],
  license = "MIT",
  homepage = "https://github.com/"..github_account_name.."/"..github_repo_name,
}

dependencies = {
  "lua >= 5.1, < 5.5",
}

build = {
  type = "builtin",

  modules = {
    ["homie45.init"] = "src/homie45/init.lua",
  },

  install = {
    bin = {
      ["homie45"] = "bin/homie45.lua",
    }
  },

  copy_directories = {
    -- can be accessed by `luarocks homie45 doc` from the commandline
    "docs",
  },
}
