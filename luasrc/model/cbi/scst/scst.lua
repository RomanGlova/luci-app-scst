local uci = luci.model.uci.cursor_state()
local sys = require "luci.sys"

--local m, s, p, b, i

math.randomseed(os.time())

m = Map("scst", translate("iSCSI target"), translate("iSCSI target"))

m:section(SimpleSection).template  = "scst_status"

function contains(t, s)
	local i,j

	for i,j in pairs(t) do
		if j == s then return true end
	end
	return false
end

function m.on_save(self)
	local devices = { }
	local sep = { }
	local scsisn
	local md5, rest, s1, s2

	self.uci:foreach("scst", "device", function(s)
		scsisn = s["scsisn"]
		if scsisn == nil then
			rest = s["path"]
			md5 = ""
			if rest then
				while scsisn == nil and rest do	
					s1,s2 = rest:match("(.-)([^\/]+)$")
					if s2 == nil then
						s2 = rest
						rest = nil
					else
						rest = s1:sub(1, -2)
					end	
					md5 = s2 .. md5
					scsisn = luci.util.exec("echo " .. md5 .. " | md5sum"):match("[0-9a-fA-F]*"):sub(-8)
				        if contains(devices, scsisn) then
						scsisn = nil
					end
				end
				self.uci:set("scst", s[".name"], "scsisn", scsisn)
			end
		end
		if scsisn then
			devices[s["name"]] = scsisn
		end
	end)
end

s = m:section(TypedSection, "global", translate("Global settings"))
s.addremove = false
s.anonymous = true

enabl = s:option(Flag, "disabled", translate("Start SCSI"), translate("Load/unload necessary kernel modules and start/stop the SCST service.".."<br />"..
	"If checkbox is not checked (by default) the modules is unloaded and service is stopped."))
enabl.rmempty  = false
enabl.default="1"
enabl.enabled="0"
enabl.disabled="1"
function enabl.write(self, section, value)
	if value == "0" then
		luci.sys.call("/etc/init.d/scst start >/dev/null")
	else
		luci.sys.call("/etc/init.d/scst stop >/dev/null")
	end

	return Flag.write(self, section, value)
end
id = s:option(Value, "id", translate("System ID"))
id.rmempty = false
id.default = "iqn.2012-12.org.openwrt"

prt = s:option(Value, "port", translate("Port"))
prt.default = ""
prt:value("", "3260 (Default)")
prt.datatype = "port"

s = m:section(TypedSection, "device", translate("Devices"),
	translate("You can create new image files with: fallocate -l &lt;size e.g. 16GB&gt; &lt;image file&gt;".."<br />"..
	"or you can use: dd if=/dev/zero bs=1G count=&lt;size in GB e.g. 16&gt; of=&lt;image file&gt;"))
s.addremove = true
s.anonymous = true
s.template = "cbi/tblsection"

devname = s:option(Value, "name", translate("<abbr title=\"Here you need to set name of device\">Name</abbr>"))
devname.rmempty = false
function devname.validate(self, value, section)
	local v = Value.formvalue(self, section)
	if v == nil or v == "" then
		return nil, translate("You must put here name of your device!")
	else
		return Value.validate(self, value, section)
	end
end

typ = s:option(ListValue, "type", translate("<abbr title=\"Choose type of device handler\">Type</abbr>"))
typ.default = "file"
typ:value("file", translate("Image file"))
typ:value("block", translate("Device"))

fl = s:option(FileBrowser, "path", translate("<abbr title=\"Select file image or device (e.g. /dev/sda)\">Path</abbr>"))
-- fl.datatype = "file"
fl.rmempty = false
fl.template = "cbi/browser_t"
function fl.validate(self, value, section)
	local v = Value.formvalue(self, section)
	if v == nil or v == "" then
		return nil, translate("You must chose file or device!")
	else
		return Value.validate(self, value, section)
	end
end
rem = s:option(Flag, "removable", translate("<abbr title=\"With this flag set the device is reported to remote initiators as removable.\nIf this attribute is enabled, device can be detached/attached without restart the SCST service.\">Removable</abbr>"))
rem.rmempty  = false
rem.default="0"
rem.enabled="1"
rem.disabled="0"
bl = s:option(ListValue, "blocksize", translate("<abbr title=\"Use 512 Byte for VMWare\">Blocksize</abbr>"))
bl.default = 512
bl:value("512", translate("512 Byte"))
bl:value("4096", translate("4 kByte"))
sn = s:option(Value, "scsisn", translate("<abbr title=\"Use 8 hex digits\">SCSI serial</abbr>"))
sn.size = 8
sn.datatype="rangelength(8,8)"
sn.validate = function(self, value)
  if #value ~= 8  then return nil end
  return value:match("^[0-9a-fA-F]+$")
end

s = m:section(TypedSection, "target", translate("Targets"))
s.addremove = true
s.anonymous = true

s:tab("general", translate("Target Setup"))
s:tab("security", translate("Security Settings"))

tgtname = s:taboption("general", Value, "name", translate("Name"))
tgtname.rmempty = false
function tgtname.validate(self, value, section)
	local v = Value.formvalue(self, section)
	if v == nil or v == "" then
		return nil, translate("You must put here name of your target!")
	else
		return Value.validate(self, value, section)
	end
end
lst = s:taboption("general", DynamicList, "lun", translate("Lun"))
m.uci:foreach("scst", "device", function(s)
	if s.name == nil then
		lst:value("", translate("TODO: Must be value"))
	else
		lst:value(s.name, s.name)
	end
end)
function lst.validate(self, value, section)
	local v = Value.formvalue(self, section)
	if v == nil or v == "" then
		return nil, translate("You must choose lun from available devices names!")
	else
		return Value.validate(self, value, section)
	end
end

auth_in = s:taboption("security", Flag, "auth_in", translate("Eanble Incoming User"), translate("Authenticate initiator"))
auth_in.enabled="1"
auth_in.disabled="0"
auth_in.default="0"
user = s:taboption("security", Value, "id_in", translate("ID"))
user.rmempty = true
user.datatype = "minlength(1)"
user:depends("auth_in", "1")
pass = s:taboption("security", Value, "secret_in", translate("Secret"), translate("Min. 12 chars."))
pass.rmempty = true
pass.datatype = "minlength(12)"
pass.password = true
pass:depends("auth_in", "1")

auth_out = s:taboption("security", Flag, "auth_out", translate("Eanble Outgoing User"), translate("Initiator requires authentication"))
auth_out.enabled="1"
auth_out.disabled="0"
auth_out.default="0"
user = s:taboption("security", Value, "id_out", translate("ID"))
user.rmempty = true
user.datatype = "minlength(1)"
user:depends("auth_out", "1")
pass = s:taboption("security", Value, "secret_out", translate("Secret"), translate("Min. 12 chars."))
pass.rmempty = true
pass.datatype = "minlength(12)"
pass.password = true
pass:depends("auth_out", "1")

ip = s:taboption("security", DynamicList, "portal", translate("Allowed Portal"), translate("Optional attribute, which specifies, on which portals"..
	"(target's IP addresses) this target will be available.".."<br />"..
	"If not specified (Default) the target will be available on all all portals."))
ip.datatype = "or(ip4addr,ip6addr,'ignore')"
ip.default=""
ip:value("", translate("Default"))
--sys.net.host_hints(function(m, v4, v6, name)
--	if v4 then
--		ip:value(v4)
--	end
--end)

for global in io.popen('ip addr show | grep global'):lines() do
	if global then
		local ip_only = global:match("^.*[inet|inet6]%s(.*)/.*$")
		ip:value(ip_only)
	end
end

--self:formvalue(section) else value = self.map:get(section, self.option)

--function ip.validate(self, value, section)
--	local cfg, form = "", ""
--	local c = ip:cfgvalue(section)
--	if c ~= nil then
--		for _, p in pairs(c) do
--			cfg = cfg..";"..p
--		end
--	end
--	local f = ip:formvalue(section)
--	if f ~= nil then 
--		for _, p in pairs(f) do
--			form = form..";"..p
--		end
--	end
--	return nil, translate("form:"..form.."cfg:"..cfg)
--	--return nil, translate("Unique address must be specified!")
--	--return Value.validate(self, value, section)
--end

return m
