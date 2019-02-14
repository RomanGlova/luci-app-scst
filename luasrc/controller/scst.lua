module("luci.controller.scst", package.seeall)

function index()
	local page

        if not nixio.fs.access("/etc/config/scst") then
		nixio.fs.writefile("/etc/config/scst", "config global 'scst'\n")
        end

	page = entry({"admin", "services", "scst"}, cbi("scst/scst"), _("iSCSI target"), 60)
	page.i18n = "scst"
	page.dependent = true

	entry({"admin", "services", "scst", "status"}, call("conn_status")).leaf = true
end

function conn_status()
	-- Funtion use ls tool to list files/dirs if path not exists return :false
	function ListDir(directory)
		local i, t, popen = 0, {}, io.popen
		local result = ""
		for filename in popen('ls -p "'..directory..'"; echo $?'):lines() do
			i = i + 1
			t[i] = filename
		end
		result = tonumber(t[#t])
		t[#t] = nil
		
		if result == 0 then
			return t
		else
			return false
		end
	end

	-- Funtion use cat tool to list content of file if file not exists return :false
	function ContentFile(file_path)
		local i, t, popen = 0, {}, io.popen
		local result = ""
		for line in popen('cat "'..file_path..'"; echo $?'):lines() do
			i = i + 1
			t[i] = line
		end
		result = tonumber(t[#t])
		t[#t] = nil
		
		if result == 0 then
			return t
		else
			return false
		end
	end

	-- Funtion list path and if it have any subpath(with regex pattern) then
	-- we add it to array and then return it. If array empty - return :false
	function ParseDirList(directory)
		local i, array = 0, {}
		for _,get_val in pairs(directory) do
			if get_val:match("^.*/$") then
				i = i + 1
				array[i] = get_val
			end
		end
		if next(array) == nil then return false
		else
			return array
		end
	end

	-- If we have one or more id_targetname then we parse inside subpath
	-- /sessions for initiator id and computername
	local path = "/sys/kernel/scst_tgt/targets/iscsi"
	--local path = "/usr/temp"
	local sub_path = "/sessions"
	local fwd, list = {}, ListDir(path)
	if list then
		local id_targetname = ParseDirList(list)
		if id_targetname then
			for id_targetnameCount = 1, #id_targetname do
				local string_path = ''..path..'/'..id_targetname[id_targetnameCount]..''..sub_path..''
				local sessions_dir = ListDir(string_path)
				local get_users = ParseDirList(sessions_dir)
				if sessions_dir and get_users then
					for get_usersCount = 1, #get_users do
						local num, id, targetname = 0, "", ""
						local initiator_name = get_users[get_usersCount]
						local initiator_name_dir = ListDir(''..string_path..'/'..initiator_name..'')
						if initiator_name_dir then
							local i, read_kb, write_kb, ip_dir = 0, 0, 0, {}
							local read_kb = ContentFile(''..string_path..'/'..initiator_name..'/read_io_count_kb')[1]
							local write_kb = ContentFile(''..string_path..'/'..initiator_name..'/write_io_count_kb')[1]
							for _,get_ip_dir in pairs(initiator_name_dir) do
								-- Cause match IPv6 type
								if get_ip_dir:match("^%[.*%]/$") then
									i = i + 1
									ip_dir[i] = get_ip_dir:match("^%[(.*)%]/$")
								-- Cause match IPv4 type
								elseif get_ip_dir:match("^%d+.%d+.%d+.%d+/$") then
									i = i + 1
									ip_dir[i] = get_ip_dir:match("^(%d+.%d+.%d+.%d+)/$")
								end

							end
							
							fwd[#fwd+1] = {
								num		= get_usersCount,
								id_targetname	= id_targetname[id_targetnameCount]:match("^(.*)/$"),
								initiator_name	= initiator_name:match("^(.*)/$"),
								ip_dir		= ip_dir,
								read_kb		= read_kb,
								write_kb	= write_kb
							}
						end
					end
				end
			end
		end
	end

	luci.http.prepare_content("application/json")
	luci.http.write_json(fwd)
end