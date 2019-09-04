require("lfs") -- Ŀ¼
require"luasql.mysql" -- mysql

-- ʱ��������ܺ�ʱ
local nTime = os.clock()

-- �ļ���Ϣ���� = {[�ļ�·��] = {�ļ���}
local tFileMsg = {}

-- ini�ļ��ļ���˳�� = {[block_id] = {�ļ���ǰ��·��}
local tIniOrder = {}

-- ������ʱ����������
local tTempBlock = {} 

-- ����mysql�Ĳ���
local tMysqlCache = {}

-- ����
function clone(object)
	local lookup_table = {}
	local function _copy(object)
		if type(object) ~= "table" then
			return object
		elseif lookup_table[object] then
			return lookup_table[object]
		end
		local newObject = {}
		lookup_table[object] = newObject
		for key, value in pairs(object) do
			newObject[_copy(key)] = _copy(value)
		end
		return setmetatable(newObject, getmetatable(object))
	end
	return _copy(object)
end

-- �ַ����ָ�
-- @string input �����ַ���
-- @string delimiter �ָ��
function split(input,delimiter)
	input = tostring(input)
	delimiter = tostring(delimiter)
	if (delimiter=='') then return false end

	local pos,arr = 0, {}
	-- for each divider found
	for st,sp in function() return string.find(input, delimiter, pos) end do
		table.insert(arr, string.sub(input, pos, st - 1))
		pos = sp + 1
	end
	table.insert(arr, string.sub(input, pos))
	return arr
end

-- mysql����
function mysqlHelper(sSql)
	if tMysqlCache[sSql] then
		return tMysqlCache[sSql]
	end

	-- ������������
	local env=luasql.mysql()

	-- �������ݿ�
	local sDatabase = "sjmy32"
	local sUser = "root"
	local sPwd = "aaa"
	local sHost = "192.168.19.38"
	local nPort = 3306
	local conn=env:connect(sDatabase,sUser,sPwd,sHost,nPort)
	if not conn then
		print("mysql connect fail")
		return
	end

	-- �������ݿ�ı����ʽ
	conn:execute"SET NAMES GB2312"

	local UD_AllData = conn:execute(sSql)
	if not UD_AllData then
		print("mysql UD_AllData Error!")
		return
	end

	-- ���ز�ѯ�����
	local tAllTabels = {}
	local tRow = UD_AllData:fetch({},"a")
	while tRow do
		-- �������idֵ����
		tAllTabels[tonumber(tRow.id)] = clone(tRow)
		-- ��ȡ��һ��
		tRow=UD_AllData:fetch(tRow,"a")
	end

	conn:close()  --�ر����ݿ�����
	env:close()   --�ر����ݿ⻷��

	return tAllTabels
end

-- ��ȡini�ļ�
function GetIniFileOrder(path,sFileName)
	local inFile = io.open(sFileName,"r")

	for line in inFile:lines() do
		local nFrom,nTo = string.find(line,"%d+")
		if nFrom and nFrom == 1 then
			local nBlockId = tonumber(string.sub(line,nFrom,nTo))
			table.insert(tTempBlock,nBlockId)

			local sNewPath = string.gsub(line,"%s","")
			local nFrom,nTo = string.find(sNewPath,"=")
			if nFrom then
				sNewPath = string.sub(sNewPath,nTo + 1,-1)
				sNewPath = path.."/"..string.gsub(sNewPath,"\\","%/")
				tIniOrder[nBlockId] = sNewPath
			end
		end
	end

	-- block����
	table.sort(tTempBlock)

	inFile:close()
end

-- �ײ�ӿ��ļ�������Ŀ¼�µ�.txt�ļ���
function GetFloorInterface(path)
	-- �����ɳ���ײ�ӿ��ļ���Ŀǰ���������ҵ����е�д���ļ���������ض��ļ�ʱ�䣩
	local sFileName = ""
	for file in lfs.dir(path) do
		if string.find(file,".txt") then
			-- �ײ�ӿ��ļ�����
			sFileName = path .. "/" .. file
			break
		end
	end

	local inFile = io.open(sFileName,"r")
	local tInterface = {}
	if inFile then
		for line in inFile:lines() do
			local nFrom,nTo = string.find(line,"Lua_%a+.%(")
			if nFrom then
				local sInterface = string.sub(line,nFrom,nTo - 1)
				tInterface[sInterface] = sInterface
			end
		end

		-- д����ӿ��ļ�
		local sWriteFile = "FloorInterface.lua"
		local outFile = io.open(sWriteFile,"w+")
		for sInf,value in pairs(tInterface) do
			if sInf == "Lua_GetParam" then
				sInf = 
[[function Lua_GetParam(nData,nConfigType)
	if nConfigType == 8000 then
		return 1908161000
	elseif nData == 2701 then
		local tRes = mysqlHelper("select id,name from cq_itemtype where id = "..nConfigType..";")
		return tRes[nConfigType] and tRes[nConfigType].name
	else
		return 0
	end
end]]
			elseif sInf == "Lua_GetLuaData" then
				sInf = [[function Lua_GetLuaData() return nil end]]
			elseif sInf == "Lua_GetFieldOccupiedFamily" then
				sInf = [[function Lua_GetFieldOccupiedFamily() return nil end]]
			else
				sInf = "function "..sInf.."() return 0 end"
			end
			outFile:write(sInf,"\n")
		end
		outFile:close()

		-- ���ȶ�ȡ����ӿ��ļ�
		dofile(sWriteFile)
	end

	inFile:close()
end

-- ��ȡ�ļ�����
function GetFileName(path)
	for file in lfs.dir(path) do
		-- print(file)

		if file == "." or file == ".." then
			-- ��Ŀ¼������
		elseif string.find(file,".lua") then
			local sFileName = path .. "/" .. file
			-- print(sFileName)
			if not tFileMsg[sFileName] then
				tFileMsg[sFileName] = file
			end
		elseif string.find(file,".ini") then
			-- ��ȡini����˳�����
			local sFileName = path .. "/" .. file
			GetIniFileOrder(path,sFileName)
		else
			-- ��Ŀ¼��������
			local sFileName = path .. "/" .. file
			GetFileName(sFileName)
		end
	end
end

-- ��ȡ�ļ���ȡ������ϵ(***��ע�͵���δ����)
local tRelBetw = {} -- �ļ����ϵ��[block_id] = {[ģ����] = {[������] = true}}
function GetFileRelactionship(nBlockId,sFileName)
	if nBlockId ~= 10004 then
		return
	end
	tRelBetw[nBlockId] = {}

	-- �����ļ���ͬʱ��ȡ�ļ���ȡ�ļ���Ĺ�����ϵ
	local inFile = io.open(sFileName,"r")
	if inFile then
		for line in inFile:lines() do
			-- ȥ���հ��ַ�
			line = string.gsub(line,"%s","")
			local nFrom0,nTo0 = string.find(line,"%-%-")
			if not nFrom0 or nFrom0 ~= 1 then
				local nFrom,nTo = string.find(line,"Lua_%d+%.")
				if nFrom then
					local sRel = string.sub(line,nFrom,nTo - 1)
					local nFrom2,nTo2 = string.find(line,"Lua_%d+%.%a+.%(")
					if nFrom2 then
						local sFunc = string.sub(line,nTo + 1,nTo2 - 1)

						if not tRelBetw[nBlockId][sRel] then
							tRelBetw[nBlockId][sRel] = {}
						end
						tRelBetw[nBlockId][sRel][sFunc] = true
					end
				end
			end
		end

		inFile:close()
	end
end

-- �����ļ�ͬʱ��ȡ������ϵ
function TestLoadfile()
	-- ˳���ȡ�ļ�
	for _,sFileName in ipairs(tTempBlock) do
		if tIniOrder[sFileName] then
			-- �����ļ�
			xpcall(dofile(tIniOrder[sFileName]),function(erroMsg)
					-- print(erroMsg)
					return true
				end)

			-- ��ȡ�ļ���ȡ������ϵ
			GetFileRelactionship(sFileName,tIniOrder[sFileName])
		end
	end
end

-- ���Է���
function testGet(path)
	-- �����ɵײ�ӿ��ļ�
	GetFloorInterface(path)
	GetFileName(path)

	-- ���Լ��������ļ�
	TestLoadfile()
end
testGet("D:/����/lua��lua�ļ�/lua���ļ�Դ�ļ�")



-- for nkey,value in pairs(_G) do
-- 	print(nkey,value)
-- 	-- if type(value) == "table" then
-- 	-- 	for nkey2,value2 in pairs(value) do
-- 	-- 		if type(value2) == "table" then
-- 	-- 			for nkey3,value3 in pairs(value2) do
-- 	-- 				print(nkey,value,nkey2,value2,nkey3,value3)
-- 	-- 			end
-- 	-- 		end
-- 	-- 	end
-- 	-- end
-- end

-- for _,value in pairs(_G.Lua_80552) do
-- 	print(_,value)
-- end
-- Lua_80552.test()


-- print(rwItemTypeGetName(1027001))
-- tRelBetw[nBlockId][sRel][sFunc] = true
for sRel,value in pairs(tRelBetw[10004]) do
	for sFunc,value2 in pairs(value) do
		-- print(sRel,sFunc)
		if _G[sRel] and _G[sRel][sFunc] and type(_G[sRel][sFunc]) == "function" then
			print(_G[sRel][sFunc],"good")
		else
			print(sRel.."."..sFunc.." bad")
		end
	end
end


print("ִ��ʱ�䣺"..(os.clock() - nTime))