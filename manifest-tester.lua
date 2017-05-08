#!/usr/bin/lua

local nixio = require('nixio')
local fs = require('nixio.fs')
local platform_info = require('platform_info')
local uci = require('uci').cursor()

local autoupdater_util = require('autoupdater.util')
local autoupdater_version = require('autoupdater.version')

if not platform_info.get_image_name() then
  io.stderr:write("The autoupdater doesn't support this hardware model.\n")
  os.exit(1)
end

local settings = uci:get_all('autoupdater', 'settings')
local branch_name = settings.branch
local mirror_name = '0'
local version_file = io.open(settings.version_file)
local old_version = version_file and version_file:read('*l') or ''
version_file:close()

local function parse_args()
  local i = 1
  while arg[i] do
     if arg[i] == '-h' then
     print("\nHelp:")
     print("This script just tells you if the manifest is valide and whether has enought valid signatures.")
     print("It reads the manifest for the branch of this nodes firmware.  It's:'" .. branch_name .."'")
     print("Arguments:")
     print("-b <BRANCH>:  test signatures against the public-keys of branch <BRANCH>")
     print("-m <url>   :  check the manifest from <url>, i.e.: 1.updates.services.fftr/firmware/tackin_test/sysupgrade")
     print("Name conventions:")
	 print("manifest-filename of 'stable' must be: stable.manifest\nmanifest-filename of 'beta' must be: beta.manifest\n")
	 os.exit(1)
     elseif arg[i] == '-m' then
      i = i+1
      if not arg[i] then
        print("Error parsing command line: expected mirror-URL")
        os.exit(1)
      end

	  mirror_name = arg[i]
    elseif arg[i] == '-b' then
      i = i+1

      if not arg[i] then
        print("Error parsing command line: expected branch name")
        os.exit(1)
      end

      branch_name = arg[i]
    else
      print("Error parsing command line: unexpected argument '" .. arg[i] .. "'")
      os.exit(1)
    end

    i = i+1
  end
end


parse_args()

local branch = uci:get_all('autoupdater', branch_name)
if not branch then
  print("Can't find configuration for branch '" .. branch_name .."'")
  os.exit(1)
end

-- Test only this signature
local function test_this_sig(lines,command_s,sig)      
      table.insert(command_s, '-s')
      table.insert(command_s, sig)
      local pid_s, f_s = autoupdater_util.popen(true, unpack(command_s))
      for _, line in ipairs(lines) do
        f_s:write(line)
        f_s:write('\n')
      end
      f_s:close()
      table.remove(command_s)
      table.remove(command_s)
      local vpid, status, code = nixio.waitpid(pid_s)
      return vpid and status == 'exited' and code == 0
end    -- End test only this sig


-- Verifies a file given as a list of lines with a list of signatures using ecdsaverify
local function verify_lines(lines, sigs)
  local command = {'ecdsaverify', '-n', tostring(branch.good_signatures)}
  local command_single = {'ecdsaverify', '-n', '1'}
  local good = tostring(branch.good_signatures)
  print("We use branch: '" .. branch_name .. "'")
  print("Minimum good signatures: '" .. good .. "'")

  -- Build command line from sigs and branch.pubkey
  for _, key in ipairs(branch.pubkey) do
    if key:match('^' .. string.rep('%x', 64) .. '$') then
      table.insert(command, '-p')
      table.insert(command, key)
      print("Found public-key: '" .. key .. "'")
      table.insert(command_single, '-p')
      table.insert(command_single, key)
    end
  end
 
  for _, sig in ipairs(sigs) do
    if sig:match('^' .. string.rep('%x', 128) .. '$') then
      table.insert(command, '-s')
      table.insert(command, sig)
      print("\nFound signature: '" .. sig .. "'")

      -- Test only this signature (does not mind duplicates)
      if test_this_sig(lines,command_single,sig) then
        print("Signature is ok!")
      else 
        print("Signature is bad!")
      end
    end
  end


  -- Call ecdsautils
  local pid, f = autoupdater_util.popen(true, unpack(command))

  for _, line in ipairs(lines) do 
    f:write(line)
    f:write('\n')
  end
  f:close()
  local wpid, status, code = nixio.waitpid(pid)
  return wpid and status == 'exited' and code == 0
end



-- Downloads, parses and verifies the update manifest from a mirror
-- Returns a table with the fields version, checksum and filename if everything is ok, nil otherwise
local function read_manifest(mirror)
  print("Read manifest from: '" .. mirror .. "'\n")

  local sep = false

  local lines = {}
  local sigs = {}

  local branch_ok = false

  local ret = {}
  -- Remove potential trailing slash
  mirror = mirror:gsub('/$', '')
  local starttime = os.time()
  local pid, manifest_loader = autoupdater_util.popen(false, 'wget', '-T', '120', '-O-', string.format('%s/%s.manifest', mirror, branch.name))

  local data = ''

  -- Read all lines from the manifest
  -- The upper part is saved to lines, the lower part to sigs
  while true do
    -- If the manifest download takes more than 1 minute, we don't really
    -- have a chance to download a whole image
    local timeout = starttime+60 - os.time()
    if timeout < 0 or not nixio.poll({{fd = manifest_loader, events = nixio.poll_flags('in')}}, timeout * 1000) then
      print("Timeout while reading manifest.\n")
      nixio.kill(pid, nixio.const.SIGTERM)
      manifest_loader:close()
      return nil
    end

    local r = manifest_loader:read(1024)
    if not r or r == '' then
      break
    end
    data = data .. r

    while data:match('\n') do
      local line, rest = data:match('^([^\n]*)\n(.*)$')
      data = rest

      if not sep then
        if line == '---' then
          sep = true
        else
          table.insert(lines, line)

          if line == ('BRANCH=' .. branch.name) then
            branch_ok = true
          end

          local date = line:match('^DATE=(.+)$')
          local priority = line:match('^PRIORITY=([%d%.]+)$')
          local model, version, checksum, filename = line:match('^([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+)$')

          if date then
            ret.date = autoupdater_util.parse_date(date)
          elseif priority then
            ret.priority = tonumber(priority)
          elseif model == platform_info.get_image_name() then
            ret.version = version
            ret.checksum = checksum
            ret.filename = filename
          end
        end
      else
        table.insert(sigs, line)
      end
    end
  end
  manifest_loader:close()

  -- Do some very basic checks before checking the signatures
  -- (as the signature verification is computationally expensive)
  if not sep then
    print('There seems to have gone something wrong downloading the manifest from ' .. mirror .. '')
    print('Or I could not find the seperator: "---" \n')
    return nil
  end

  if not ret.date or not ret.priority then
    print('The manifest downloaded from ' .. mirror .. ' is invalid (DATE or PRIORITY missing)\n')
    return nil
  end

  if not branch_ok then
    print('Wrong branch. We are on: ', branch.name, '')
    return nil
  end

  if not ret.version then
    print('No matching firmware found (model ' .. platform_info.get_image_name() .. ')')
    return nil
  end

  if not verify_lines(lines, sigs) then
    print('\nNot enough valid signatures!\n')
    return nil
  else 
  -- we are good to go
    print('\nEnough valid signatures!\n')
  end

  return ret
end


-- Tries to perform an update from a given mirror
local function autoupdate(mirror)

  local manifest = read_manifest(mirror)
  if not manifest then
    print('No good manifest found!')
    return false
  end

  if not autoupdater_version.newer_than(manifest.version, old_version) then
    print('No new firmware available.')
    return true
  end

  print('New version available.')

end

if mirror_name ~= '0'  then
   print('\nGiven url: ' .. mirror_name .. '')
 
  if autoupdate(mirror_name) then
    os.exit(0)
  end
else
 local mirrors = branch.mirror
 while #mirrors > 0 do
    local mirror = table.remove(mirrors, math.random(#mirrors))
    if autoupdate(mirror) then
      os.exit(0)
    end
  end
end
print('Sorry.')
os.exit(1)
