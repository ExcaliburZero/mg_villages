-- this contains the functions to actually generate the village structure in a table;
-- said table will hold information about which building will be placed where,
-- how the buildings are rotated, where the roads will be, which replacement materials
-- will be used etc.

local function is_village_block(minp)
	local x, z = math.floor(minp.x/80), math.floor(minp.z/80)
	local vcc = mg_villages.VILLAGE_CHECK_COUNT
	return (x%vcc == 0) and (z%vcc == 0)
end

-- called by mapgen.lua and spawn_player.lua
mg_villages.villages_at_point = function(minp, noise1)
	if not is_village_block(minp) then return {} end
	local vcr, vcc = mg_villages.VILLAGE_CHECK_RADIUS, mg_villages.VILLAGE_CHECK_COUNT
	-- Check if there's another village nearby
	for xi = -vcr, vcr, vcc do
	for zi = -vcr, 0, vcc do
		if xi ~= 0 or zi ~= 0 then
			local mp = {x = minp.x + 80*xi, z = minp.z + 80*zi}
			local pi = PseudoRandom(mg_villages.get_bseed(mp))
			local s = pi:next(1, 400)
			local x = pi:next(mp.x, mp.x + 79)
			local z = pi:next(mp.z, mp.z + 79)
			if s <= mg_villages.VILLAGE_CHANCE and noise1:get2d({x = x, y = z}) >= -0.3 then return {} end
		end
	end
	end
	local pr = PseudoRandom(mg_villages.get_bseed(minp))
	if pr:next(1, 400) > mg_villages.VILLAGE_CHANCE then return {} end -- No village here
	local x = pr:next(minp.x, minp.x + 79)
	local z = pr:next(minp.z, minp.z + 79)
	if noise1:get2d({x = x, y = z}) < -0.3 then return {} end -- Deep in the ocean

	-- fallback: type "nore" (that is what the mod originally came with)
	local village_type = 'nore';
	-- if this is the first village for this world, take a medieval one
	if( (not( mg_villages.all_villages ) or mg_villages.anz_villages < 1) and minetest.get_modpath("cottages") ) then
		village_type = 'medieval';
	else
		village_type = mg_villages.village_types[ pr:next(1, #mg_villages.village_types )]; -- select a random type
	end

	if( not( mg_villages.village_sizes[ village_type ] )) then
		mg_villages.village_sizes[  village_type ] = { min = mg_villages.VILLAGE_MIN_SIZE, max = mg_villages.VILLAGE_MAX_SIZE };
	end
	local size = pr:next(mg_villages.village_sizes[ village_type ].min, mg_villages.village_sizes[ village_type ].max) 
--	local height = pr:next(5, 20)
	local height = pr:next(1, 5)
	-- villages of a size >= 40 are always placed at a height of 1
	if(     size >= 40 ) then
		height = 1;
	-- slightly smaller but still relatively large villages have a deterministic height now as well
	elseif( size >= 30 ) then
		height = 40-height;
	elseif( size >= 25 ) then
		height = 35-height;
	-- even smaller villages need to have a height depending on their sourroundings (at least they're pretty small!)
	end

--	print("A village of type \'"..tostring( village_type ).."\' of size "..tostring( size ).." spawned at: x = "..x..", z = "..z)
	--print("A village spawned at: x = "..x..", z = "..z)
	return {{vx = x, vz = z, vs = size, vh = height, village_type = village_type}}
end

--local function dist_center2(ax, bsizex, az, bsizez)
--	return math.max((ax+bsizex)*(ax+bsizex),ax*ax)+math.max((az+bsizez)*(az+bsizez),az*az)
--end

local function inside_village2(bx, sx, bz, sz, village, vnoise)
	return mg_villages.inside_village(bx, bz, village, vnoise) and mg_villages.inside_village(bx+sx, bz, village, vnoise) and mg_villages.inside_village(bx, bz+sz, village, vnoise) and mg_villages.inside_village(bx+sx, bz+sz, village, vnoise)
end

local function choose_building(l, pr, village_type)
	--::choose::
	local btype
	while true do
		local p = pr:next(1, 3000)
		for b, i in ipairs(mg_villages.BUILDINGS) do
			if i.weight[ village_type ] and i.weight[ village_type ] > 0 and i.max_weight and i.max_weight[ village_type ] and i.max_weight[ village_type ] >= p then
				btype = b
				break
			end
		end
		-- in case no building was found: take the last one that fits
		if( not( btype )) then
			for i=#mg_villages.BUILDINGS,1,-1 do
				if( mg_villages.BUILDINGS[i].weight and mg_villages.BUILDINGS[i].weight[ village_type ] and mg_villages.BUILDINGS[i].weight[ village_type ] > 0 ) then
					btype = i;
					i = 1;
				end
			end
		end
		if( not( btype )) then
			return 1;
		end
		if( #l<1
			or not( mg_villages.BUILDINGS[btype].avoid )
			or mg_villages.BUILDINGS[btype].avoid==''
			or not( mg_villages.BUILDINGS[ l[#l].btype ].avoid )
			or mg_villages.BUILDINGS[btype].avoid ~= mg_villages.BUILDINGS[ l[#l].btype ].avoid) then

			if mg_villages.BUILDINGS[btype].pervillage ~= nil then
				local n = 0
				for j=1, #l do
					if( l[j].btype == btype or (mg_villages.BUILDINGS[btype].typ and mg_villages.BUILDINGS[btype].typ == mg_villages.BUILDINGS[ l[j].btype ].typ)) then
						n = n + 1
					end
				end
				--if n >= mg_villages.BUILDINGS[btype].pervillage then
				--	goto choose
				--end
				if n < mg_villages.BUILDINGS[btype].pervillage then
					return btype
				end
			else
				return btype
			end
		end
	end
	--return btype
end

local function choose_building_rot(l, pr, orient, village_type)
	local btype = choose_building(l, pr, village_type)
	local rotation
	if mg_villages.BUILDINGS[btype].no_rotate then
		rotation = 0
	else
		if mg_villages.BUILDINGS[btype].orients == nil then
			mg_villages.BUILDINGS[btype].orients = {0,1,2,3}
		end
		rotation = (orient+mg_villages.BUILDINGS[btype].orients[pr:next(1, #mg_villages.BUILDINGS[btype].orients)])%4
	end
	local bsizex = mg_villages.BUILDINGS[btype].sizex
	local bsizez = mg_villages.BUILDINGS[btype].sizez
	if rotation%2 == 1 then
		bsizex, bsizez = bsizez, bsizex
	end
	-- some buildings are mirrored
	local mirror = nil;
	if( pr:next( 1,2 )==1 ) then
		mirror = true;
	end
	return btype, rotation, bsizex, bsizez, mirror
end

local function placeable(bx, bz, bsizex, bsizez, l, exclude_roads, orientation)
	for _, a in ipairs(l) do
		-- with < instead of <=, space_between_buildings can be zero (important for towns where houses are closely packed)
		if (a.btype ~= "road" or not exclude_roads) and math.abs(bx+bsizex/2-a.x-a.bsizex/2)<(bsizex+a.bsizex)/2 and math.abs(bz+bsizez/2-a.z-a.bsizez/2)<(bsizez+a.bsizez)/2 then
			-- dirt roads which go at a 90 degree angel to the current road are not a problem
			if( not( orientation ) or a.o%2 == orientation%2 ) then
				return false
			end
		end
	end
	return true
end

local function road_in_building(rx, rz, rdx, rdz, roadsize, l)
	if rdx == 0 then
		return not placeable(rx-roadsize+1, rz, 2*roadsize-2, 0, l, true)
	else
		return not placeable(rx, rz-roadsize+1, 0, 2*roadsize-2, l, true)
	end
end

local function when(a, b, c)
	if a then return b else return c end
end

mg_villages.road_nr = 0;

local function generate_road(village, l, pr, roadsize, rx, rz, rdx, rdz, vnoise, space_between_buildings)
	local vx, vz, vh, vs = village.vx, village.vz, village.vh, village.vs
	local village_type   = village.village_type;
	local calls_to_do = {}
	local rxx = rx
	local rzz = rz
	local mx, m2x, mz, m2z, mmx, mmz
	mx, m2x, mz, m2z = rx, rx, rz, rz
	local orient1, orient2
	if rdx == 0 then
		orient1 = 0
		orient2 = 2
	else
		orient1 = 3
		orient2 = 1
	end
	-- we have one more road
	mg_villages.road_nr = mg_villages.road_nr + 1;
	while mg_villages.inside_village(rx, rz, village, vnoise) and not road_in_building(rx, rz, rdx, rdz, roadsize, l) do
		if roadsize > 1 and pr:next(1, 4) == 1 then
			--generate_road(vx, vz, vs, vh, l, pr, roadsize-1, rx, rz, math.abs(rdz), math.abs(rdx))
			calls_to_do[#calls_to_do+1] = {rx=rx+(roadsize - 1)*rdx, rz=rz+(roadsize - 1)*rdz, rdx=math.abs(rdz), rdz=math.abs(rdx)}
			m2x = rx + (roadsize - 1)*rdx
			m2z = rz + (roadsize - 1)*rdz
			rx = rx + (2*roadsize - 1)*rdx
			rz = rz + (2*roadsize - 1)*rdz
		end
		--else
			--::loop::
			local exitloop = false
			local bx
			local bz
			local tries = 0
			while true do
				if not mg_villages.inside_village(rx, rz, village, vnoise) or road_in_building(rx, rz, rdx, rdz, roadsize, l) then
					exitloop = true
					break
				end
				local village_type_sub = village_type;
				if( mg_villages.medieval_subtype and village_type_sub == 'medieval' and math.abs(village.vx-rx)>20 and math.abs(village.vz-rz)>20) then
					village_type_sub = 'fields';
				end
				btype, rotation, bsizex, bsizez, mirror = choose_building_rot(l, pr, orient1, village_type_sub)
				bx = rx + math.abs(rdz)*(roadsize+1) - when(rdx==-1, bsizex-1, 0)
				bz = rz + math.abs(rdx)*(roadsize+1) - when(rdz==-1, bsizez-1, 0)
				if placeable(bx, bz, bsizex, bsizez, l) and inside_village2(bx, bsizex, bz, bsizez, village, vnoise) then
					break
				end
				if tries > 5 then
					rx = rx + rdx
					rz = rz + rdz
					tries = 0
				else
					tries = tries + 1
				end
				--goto loop
			end
			if exitloop then break end
			rx = rx + (bsizex+space_between_buildings)*rdx
			rz = rz + (bsizez+space_between_buildings)*rdz
			mx = rx - 2*rdx
			mz = rz - 2*rdz
			l[#l+1] = {x=bx, y=vh, z=bz, btype=btype, bsizex=bsizex, bsizez=bsizez, brotate = rotation, road_nr = mg_villages.road_nr, side=1, o=orient1, mirror=mirror }
		--end
	end
	rx = rxx
	rz = rzz
	while mg_villages.inside_village(rx, rz, village, vnoise) and not road_in_building(rx, rz, rdx, rdz, roadsize, l) do
		if roadsize > 1 and pr:next(1, 4) == 1 then
			--generate_road(vx, vz, vs, vh, l, pr, roadsize-1, rx, rz, -math.abs(rdz), -math.abs(rdx))
			calls_to_do[#calls_to_do+1] = {rx=rx+(roadsize - 1)*rdx, rz=rz+(roadsize - 1)*rdz, rdx=-math.abs(rdz), rdz=-math.abs(rdx)}
			m2x = rx + (roadsize - 1)*rdx
			m2z = rz + (roadsize - 1)*rdz
			rx = rx + (2*roadsize - 1)*rdx
			rz = rz + (2*roadsize - 1)*rdz
		end
		--else
			--::loop::
			local exitloop = false
			local bx
			local bz
			local tries = 0
			while true do
				if not mg_villages.inside_village(rx, rz, village, vnoise) or road_in_building(rx, rz, rdx, rdz, roadsize, l) then
					exitloop = true
					break
				end
				local village_type_sub = village_type;
				if( mg_villages.medieval_subtype and village_type_sub == 'medieval' and math.abs(village.vx-rx)>(village.vs/3) and math.abs(village.vz-rz)>(village.vs/3)) then
					village_type_sub = 'fields';
				end
				btype, rotation, bsizex, bsizez, mirror = choose_building_rot(l, pr, orient2, village_type_sub)
				bx = rx - math.abs(rdz)*(bsizex+roadsize) - when(rdx==-1, bsizex-1, 0)
				bz = rz - math.abs(rdx)*(bsizez+roadsize) - when(rdz==-1, bsizez-1, 0)
				if placeable(bx, bz, bsizex, bsizez, l) and inside_village2(bx, bsizex, bz, bsizez, village, vnoise) then
					break
				end
				if tries > 5 then
					rx = rx + rdx
					rz = rz + rdz
					tries = 0
				else
					tries = tries + 1
				end
				--goto loop
			end
			if exitloop then break end
			rx = rx + (bsizex+space_between_buildings)*rdx
			rz = rz + (bsizez+space_between_buildings)*rdz
			m2x = rx - 2*rdx
			m2z = rz - 2*rdz
			l[#l+1] = {x=bx, y=vh, z=bz, btype=btype, bsizex=bsizex, bsizez=bsizez, brotate = rotation, road_nr = mg_villages.road_nr, side=2, o=orient2, mirror=mirror}
		--end
	end
	if road_in_building(rx, rz, rdx, rdz, roadsize, l) then
		mmx = rx - 2*rdx
		mmz = rz - 2*rdz
	end
	mx = mmx or rdx*math.max(rdx*mx, rdx*m2x)
	mz = mmz or rdz*math.max(rdz*mz, rdz*m2z)
	if rdx == 0 then
		rxmin = rx - roadsize + 1
		rxmax = rx + roadsize - 1
		rzmin = math.min(rzz, mz)
		rzmax = math.max(rzz, mz)
		-- prolong the main road to the borders of the village
		if( mg_villages.road_nr == 1 ) then	
			while( mg_villages.inside_village_area(rxmin, rzmin, village, vnoise)) do
				rzmin = rzmin-1;
				rzmax = rzmax+1;
			end
			rzmin = rzmin-1;
			rzmax = rzmax+1;
			while( mg_villages.inside_village_area(rxmax, rzmax, village, vnoise)) do
				rzmax = rzmax+1;
			end
			rzmax = rzmax+1;
		end
	else
		rzmin = rz - roadsize + 1
		rzmax = rz + roadsize - 1
		rxmin = math.min(rxx, mx)
		rxmax = math.max(rxx, mx)
		-- prolong the main road to the borders of the village
		if( mg_villages.road_nr == 1 ) then	
			while( mg_villages.inside_village_area(rxmin, rzmin, village, vnoise)) do
				rxmin = rxmin-1;
				rxmax = rxmax+1;
			end
			rxmin = rxmin-1;
			rxmax = rxmax+1;
			while( mg_villages.inside_village_area(rxmax, rzmax, village, vnoise)) do
				rxmax = rxmax+1;
			end
			rxmax = rxmax+1;
		end
	end
	l[#l+1] = {x = rxmin, y = vh, z = rzmin, btype = "road",
		bsizex = rxmax - rxmin + 1, bsizez = rzmax - rzmin + 1, brotate = 0, road_nr = mg_villages.road_nr}
	
	for _, i in ipairs(calls_to_do) do
		local new_roadsize = roadsize - 1
		if pr:next(1, 100) <= mg_villages.BIG_ROAD_CHANCE then
			new_roadsize = roadsize
		end

		--generate_road(vx, vz, vs, vh, l, pr, new_roadsize, i.rx, i.rz, i.rdx, i.rdz, vnoise)
		calls[calls.index] = {village, l, pr, new_roadsize, i.rx, i.rz, i.rdx, i.rdz, vnoise, space_between_buildings}
		calls.index = calls.index+1
	end
end

local function generate_bpos(village, pr, vnoise, space_between_buildings)
	local vx, vz, vh, vs = village.vx, village.vz, village.vh, village.vs
	local l = {}
	local rx = vx - vs
	--[=[local l={}
	local total_weight = 0
	for _, i in ipairs(mg_villages.BUILDINGS) do
		if i.weight == nil then i.weight = 1 end
		total_weight = total_weight+i.weight
		i.max_weight = total_weight
	end
	local multiplier = 3000/total_weight
	for _,i in ipairs(mg_villages.BUILDINGS) do
		i.max_weight = i.max_weight*multiplier
	end
	for i=1, 2000 do
		bx = pr:next(vx-vs, vx+vs)
		bz = pr:next(vz-vs, vz+vs)
		::choose::
		--[[btype = pr:next(1, #mg_villages.BUILDINGS)
		if mg_villages.BUILDINGS[btype].chance ~= nil then
			if pr:next(1, mg_villages.BUILDINGS[btype].chance) ~= 1 then
				goto choose
			end
		end]]
		p = pr:next(1, 3000)
		for b, i in ipairs(mg_villages.BUILDINGS) do
			if i.max_weight > p then
				btype = b
				break
			end
		end
		if mg_villages.BUILDINGS[btype].pervillage ~= nil then
			local n = 0
			for j=1, #l do
				if l[j].btype == btype then
					n = n + 1
				end
			end
			if n >= mg_villages.BUILDINGS[btype].pervillage then
				goto choose
			end
		end
		local rotation
		if mg_villages.BUILDINGS[btype].no_rotate then
			rotation = 0
		else
			rotation = pr:next(0, 3)
		end
		bsizex = mg_villages.BUILDINGS[btype].sizex
		bsizez = mg_villages.BUILDINGS[btype].sizez
		if rotation%2 == 1 then
			bsizex, bsizez = bsizez, bsizex
		end
		if dist_center2(bx-vx, bsizex, bz-vz, bsizez)>vs*vs then goto out end
		for _, a in ipairs(l) do
			if math.abs(bx-a.x)<=(bsizex+a.bsizex)/2+2 and math.abs(bz-a.z)<=(bsizez+a.bsizez)/2+2 then goto out end
		end
		l[#l+1] = {x=bx, y=vh, z=bz, btype=btype, bsizex=bsizex, bsizez=bsizez, brotate = rotation}
		::out::
	end
	return l]=]--
	local rz = vz
	while mg_villages.inside_village(rx, rz, village, vnoise) do
		rx = rx - 1
	end
	rx = rx + 5
	calls = {index = 1}
	-- the function below is recursive; we need a way to count roads
	mg_villages.road_nr = 0;
	generate_road(village, l, pr, mg_villages.FIRST_ROADSIZE, rx, rz, 1, 0, vnoise, space_between_buildings)
	i = 1
	while i < calls.index do
		generate_road(unpack(calls[i]))
		i = i+1
	end
	mg_villages.road_nr = 0;
	return l
end


-- dirt roads seperate the wheat area around medieval villages into seperate fields and make it look better
local function generate_dirt_roads = function( village, vnoise, bpos, secondary_dirt_roads )
	local dirt_roads = {};
	if( not( secondary_dirt_roads)) then
		return dirt_roads;
	end
	for _, pos in ipairs( bpos ) do

		local x = pos.x;
		local z = pos.z; 
		local sizex = pos.bsizex;
		local sizez = 2;
		local orientation = 0;
		-- prolong the roads; start with a 3x2 piece of road for testing
		if( pos.btype == 'road' ) then
			-- the road streches in x direction
			if( pos.bsizex > pos.bsizez ) then
				sizex = 3; -- start with a road of length 3
				sizez = 2;
				vx    = -1; vz    = 0; vsx   = 1; vsz   = 0;
				x     = pos.x - sizex;
				z     = pos.z + math.floor((pos.bsizez-2)/2); -- aim for the middle of the road
				orientation = 0;
				-- if it is not possible to prolong the road at one end, then try the other
				if( not( placeable( x, z, sizex, sizez, bpos,       false, nil))) then
					x = pos.x + pos.bsizex;
					vx = 0;
					orientation = 2;
				end
			-- the road stretches in z direction
			else
				sizex = 2;
				sizez = 3;
				vx    = 0;  vz = -1; vsx   = 0; vsz   = 1;
				x     = pos.x + math.floor((pos.bsizex-2)/2); -- aim for the middle of the road
				z     = pos.z - sizez;
				orientation = 1;
				if( not( placeable( x, z, sizex, sizez, bpos,       false, nil))) then
					z = pos.z + pos.bsizez;
					vz = 0;
					orientation = 3;
				end
			end
				
		else
			if(     pos.o == 0 ) then
				x = pos.x-pos.side;
				z = pos.z-2; 
				sizex = pos.bsizex+1;
				sizez = 2;
				vx = 0; vz = 0;  vsx = 1; vsz = 0;

			elseif( pos.o == 2 ) then
				x = pos.x-pos.side+2;
				z = pos.z-2; 
				sizex = pos.bsizex+1;
				sizez = 2;
				vx = -1; vz = 0;  vsx = 1; vsz = 0;

			elseif( pos.o == 1 ) then
				x = pos.x-2;
				z = pos.z-pos.side+2; 
				sizex = 2;
				sizez = pos.bsizez+1;
				vx = 0;  vz = -1; vsx = 0; vsz = 1;

			elseif( pos.o == 3 ) then
				x = pos.x-2;
				z = pos.z-pos.side; 
				sizex = 2;
				sizez = pos.bsizez+1;
				vx = 0;  vz = 0;  vsx = 0; vsz = 1;
			end
			orientation = pos.o;

		end

		-- prolong the dirt road by 1
		while( placeable( x, z, sizex, sizez, bpos,       false, nil)
		   and placeable( x, z, sizex, sizez, dirt_roads, false, orientation)
 		   and mg_villages.inside_village_area(x, z, village, vnoise)
 		   and mg_villages.inside_village_area(x+sizex, z+sizez, village, vnoise)) do
			sizex = sizex + vsx;
			sizez = sizez + vsz;
			x     = x + vx;
			z     = z + vz;
		end

		-- the dirt road may exceed the village boundaries slightly, but it may not interfere with other buildings
		if(   not( placeable( x, z, sizex, sizez, bpos,       false, nil))
		   or not( placeable( x, z, sizex, sizez, dirt_roads, false, orientation))) then
			sizex = sizex - vsx;
			sizez = sizez - vsz;
			x     = x - vx;
			z     = z - vz;
		end

		if(    placeable( x, z, sizex, sizez, bpos,       false, nil)  
		   and placeable( x, z, sizex, sizez, dirt_roads, false, orientation)) then 
			dirt_roads[#dirt_roads+1] = {x=x, y=village.vh, z=z, btype="dirt_road", bsizex=sizex, bsizez=sizez, brotate = 0, o=orientation}
		end
	end
	return dirt_roads;
end




local MIN_DIST = 1

local function pos_far_buildings(x, z, l)
	for _, a in ipairs(l) do
		if a.x - MIN_DIST <= x and x <= a.x + a.bsizex + MIN_DIST and
		   a.z - MIN_DIST <= z and z <= a.z + a.bsizez + MIN_DIST then
			return false
		end
	end
	return true
end


local function generate_walls(bpos, data, a, minp, maxp, vh, vx, vz, vs, vnoise)
	for x = minp.x, maxp.x do
	for z = minp.z, maxp.z do
		local xx = (vnoise:get2d({x=x, y=z})-2)*20+(40/(vs*vs))*((x-vx)*(x-vx)+(z-vz)*(z-vz))
		if xx>=40 and xx <= 44 then
			bpos[#bpos+1] = {x=x, z=z, y=vh, btype="wall", bsizex=1, bsizez=1, brotate=0}
		end
	end
	end
end


-- determine which building is to be placed where
-- also choose which blocks to replace with which other blocks (to make villages more intresting)
mg_villages.generate_village = function(village, vnoise)
	local vx, vz, vs, vh = village.vx, village.vz, village.vs, village.vh
	local village_type = village.village_type;
	local seed = mg_villages.get_bseed({x=vx, z=vz})
	local pr_village = PseudoRandom(seed)

	-- generate a name for the village
	village.name = namegen.generate_village_name( pr_village );

	-- only generate a new village if the data is not already stored
	-- (the algorithm is fast, but village types and houses which are available may change later on,
  	-- and that might easily cause chaos if the village is generated again with diffrent input)
	if( village.to_add_data and village.to_add_data.bpos and village.to_add_data.replacements and village.to_add_data.plantlist) then
		--print('VILLAGE GENREATION: USING ALREADY GENERATED VILLAGE: Nr. '..tostring( village.nr )); 
		return;
	end

	-- in the case of medieval villages, we later on want to add wheat fields with dirt roads; 1 wide dirt roads look odd
	local space_between_buildings = mg_villages.village_sizes[ village_type ].space_between_buildings;

	-- actually generate the village structure
	local bpos = generate_bpos( village, pr_village, vnoise, space_between_buildings)


	local secondary_dirt_roads = nil; 
	-- if there is enough space, add dirt roads between the buildings (those will later be prolonged so that they reach the fields)
	if( space_between_buildings >= 2 and village_type == 'medieval') then
		secondary_dirt_roads = "dirt_road";
	end

	local dirt_roads = generate_dirt_roads( village, vnoise, bpos, secondary_dirt_roads );

	-- set fruits for all buildings in the village that need it - regardless weather they will be spawned
	-- now or later; after the first call to this function here, the village data will be final
	for _, pos in ipairs( bpos ) do
		local binfo = mg_villages.BUILDINGS[pos.btype];
		if( binfo.farming_plus and binfo.farming_plus == 1 and mg_villages.fruit_list and not pos.furit) then
 			pos.fruit = mg_villages.fruit_list[ pr_village:next( 1, #mg_villages.fruit_list )];
		end
	end

	-- a changing replacement list would also be pretty confusing
	local p = PseudoRandom(seed);
	-- if the village is new, replacement_list is nil and a new replacement list will be created
	local replacements = mg_villages.get_replacement_table( village.village_type, p, nil );
	
	-- determine which plants will grow in the area around the village
	local plantlist = {};
	sapling_id = mg_villages.get_content_id_replaced( 'default:sapling', replacements );
	-- 1/sapling_p = probability of a sapling beeing placed
	local sapling_p  = 25;
	if( mg_villages.sapling_probability[ sapling_id ] ) then
		sapling_p = mg_villages.sapling_probability[ sapling_id ];
	end

	-- medieval villages are sourrounded by wheat fields
	if(     village_type == 'medieval' ) then
		local c_wheat = mg_villages.get_content_id_replaced( 'farming:wheat_8', replacements);
		plantlist = {
			{ id=sapling_id, p=sapling_p*10 }, -- trees are rather rare
			{ id=c_wheat,    p=1         }};
	-- lumberjack camps have handy trees nearby
	elseif( village_type == 'lumberjack' ) then
		local c_junglegrass = mg_villages.get_content_id_replaced( 'default:junglegrass', replacements);
		plantlist = {
			{ id=sapling_id,    p=sapling_p },
			{ id=c_junglegrass, p=25        }};
	-- the villages of type taoki grow cotton
	elseif( village_type == 'taoki' ) then
		local c_cotton = mg_villages.get_content_id_replaced( 'farming:cotton_8', replacements);
		plantlist = {
			{ id=sapling_id, p=sapling_p*5 }, -- not too many trees
			{ id=c_cotton,   p=1         }};
	-- default/fallback: grassland
	else
		local c_grass = mg_villages.get_content_id_replaced( 'default:grass_5', replacements);
		plantlist = {
			{ id=sapling_id, p=sapling_p*10}, -- only few trees
			{ id=c_grass,    p=3         }};
	end

	-- store the generated data in the village table 
	village.to_add_data               = {};
	village.to_add_data.bpos          = bpos;
	village.to_add_data.replacements  = replacements.list;
	village.to_add_data.dirt_roads    = dirt_roads;
	village.to_add_data.plantlist     = plantlist;

	--print('VILLAGE GENREATION: GENERATING NEW VILLAGE Nr. '..tostring( village.nr ));
end

