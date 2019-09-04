require("lfs") -- 目录
require"luasql.mysql" -- mysql

-- 时间戳计算总耗时
local nTime = os.clock()

-- 文件信息数据 = {[文件路径] = {文件名}
local tFileMsg = {}

-- ini文件的加载顺序 = {[block_id] = {文件当前的路径}
local tIniOrder = {}

-- 索引临时表用于排序
local tTempBlock = {} 

-- 缓存mysql的操作
local tMysqlCache = {}

-- 表复制
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

-- 字符串分割
-- @string input 输入字符串
-- @string delimiter 分割符
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

-- mysql操作
function mysqlHelper(sSql)
	if tMysqlCache[sSql] then
		return tMysqlCache[sSql]
	end

	-- 创建环境对象
	local env=luasql.mysql()

	-- 连接数据库
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

	-- 设置数据库的编码格式
	conn:execute"SET NAMES GB2312"

	local UD_AllData = conn:execute(sSql)
	if not UD_AllData then
		print("mysql UD_AllData Error!")
		return
	end

	-- 返回查询结果集
	local tAllTabels = {}
	local tRow = UD_AllData:fetch({},"a")
	while tRow do
		-- 结果集以id值返回
		tAllTabels[tonumber(tRow.id)] = clone(tRow)
		-- 读取下一条
		tRow=UD_AllData:fetch(tRow,"a")
	end

	conn:close()  --关闭数据库连接
	env:close()   --关闭数据库环境

	return tAllTabels
end

-- 读取ini文件
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

	-- block排序
	table.sort(tTempBlock)

	inFile:close()
end

-- 底层接口文件构建（目录下的.txt文件）
function GetFloorInterface(path)
	-- 先生成程序底层接口文件（目前先用正则找到所有的写入文件处理减少重读文件时间）
	local sFileName = ""
	for file in lfs.dir(path) do
		if string.find(file,".txt") then
			-- 底层接口文件构建
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

		-- 写程序接口文件
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

		-- 优先读取程序接口文件
		dofile(sWriteFile)
	end

	inFile:close()
end

-- 获取文件名字
function GetFileName(path)
	for file in lfs.dir(path) do
		-- print(file)

		if file == "." or file == ".." then
			-- 跟目录不处理
		elseif string.find(file,".lua") then
			local sFileName = path .. "/" .. file
			-- print(sFileName)
			if not tFileMsg[sFileName] then
				tFileMsg[sFileName] = file
			end
		elseif string.find(file,".ini") then
			-- 读取ini用于顺序加载
			local sFileName = path .. "/" .. file
			GetIniFileOrder(path,sFileName)
		else
			-- 子目录继续检索
			local sFileName = path .. "/" .. file
			GetFileName(sFileName)
		end
	end
end

-- 读取文件获取关联关系(***块注释的暂未处理)
local tRelBetw = {} -- 文件间关系表[block_id] = {[模块名] = {[方法名] = true}}
function GetFileRelactionship(nBlockId,sFileName)
	if nBlockId ~= 10004 then
		return
	end
	tRelBetw[nBlockId] = {}

	-- 加载文件的同时读取文件获取文件间的关联关系
	local inFile = io.open(sFileName,"r")
	if inFile then
		for line in inFile:lines() do
			-- 去掉空白字符
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

-- 加载文件同时获取关联关系
function TestLoadfile()
	-- 顺序读取文件
	for _,sFileName in ipairs(tTempBlock) do
		if tIniOrder[sFileName] then
			-- 加载文件
			xpcall(dofile(tIniOrder[sFileName]),function(erroMsg)
					-- print(erroMsg)
					return true
				end)

			-- 读取文件获取关联关系
			GetFileRelactionship(sFileName,tIniOrder[sFileName])
		end
	end
end

-- 测试方法
function testGet(path)
	-- 先生成底层接口文件
	GetFloorInterface(path)
	GetFileName(path)

	-- 测试加载所有文件
	TestLoadfile()
end
testGet("D:/桌面/lua读lua文件/lua读文件源文件")



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


print("执行时间："..(os.clock() - nTime))