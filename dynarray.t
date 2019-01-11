
--Dynamic arrays for Terra.
--Written by Cosmin Apreutesei. Public domain.

if not ... then require'dynarray_test'; return end

local function dynarray_type(T, size_t, growth_factor, C)

	setfenv(1, C)

	local arr = struct {
		data: &T;
		size: size_t;
		len: size_t;
	}

	--storage

	function arr.metamethods.__cast(from, to, exp)
		if from == (`{}):gettype() then --initalize with empty tuple
			return `arr {nil, 0, 0}
		end
	end

	arr.methods.isslice = macro(function(self) return `self.size < 0 end)

	terra arr:realloc(size: size_t): bool
		check(size >= 0)
		if self:isslice() then
			return size <= self.len
		end
		if size == self.size then return true end
		if size > self.size then --grow
			size = max(size, self.size * growth_factor)
		end
		var new_data = [&T](realloc(self.data, sizeof(T) * size))
		if size > 0 and new_data == nil then return false end
		self.data = new_data
		self.size = size
		self.len = min(size, self.len)
		return true
	end

	terra arr:free()
		self:realloc(0)
	end

	terra arr:shrink()
		if self.size == self.len then return true end
		return self:realloc(self.len)
	end

	--random access

	arr.metamethods.__apply = terra(self: &arr, i: size_t): &T
		if i < 0 then i = self.len - i end
		check(i >= 0 and i < self.len)
		return &self.data[i]
	end

	terra arr:get(i: size_t): T
		if i < 0 then i = self.len - i end
		check(i >= 0 and i < self.len)
		return self.data[i]
	end

	terra arr:grow(i: size_t): bool
		check(i >= 0)
		if i >= self.size then --grow capacity
			if not self:realloc(i+1) then
				return false
			end
		end
		if i >= self.len then --enlarge
			if i >= self.len + 1 then --clear the gap
				memset(self.data + self.len, 0, sizeof(T) * (i - self.len))
			end
			self.len = i + 1
		end
		return true
	end

	terra arr:set(i: size_t, val: T): bool
		if i < 0 then i = self.len - i end
		if self:isslice() then check(i < self.len) end
		if not self:grow(i) then return false end
		self.data[i] = val
		return true
	end

	--ordered access

	arr.metamethods.__for = function(self, body)
		return quote
			for i = 0, self.len do
				[ body(`i, `self.data[i]) ]
			end
		end
	end

	--stack interface

	terra arr:push(val: T)
		return self:set(self.len, val)
	end

	terra arr:pop()
		var v = self:get(-1)
		self.len = self.len - 1
		return v
	end

	--segment shifting

	local insert = terralib.overloadedfunction('insert', {})
	arr.methods.insert = insert

	insert:adddefinition(
		terra(self: &arr, i: size_t, n: size_t)
			if i < 0 then i = self.len - i end
			check(i >= 0 and n >= 0)
			var b = max(0, self.len-i) --how many bytes must be moved
			if not self:realloc(max(self.size, i+n+b)) then return false end
			if b <= 0 then return true end
			memmove(self.data+i+n, self.data+i, b)
			return true
		end)

	terra arr:remove(i: size_t, n: size_t)
		if i < 0 then i = self.len - i end
		check(i >= 0 and n >= 0)
		if n >= self.len-i-1 then return end
		memmove(self.data+i, self.data+i+n, self.len-i-n)
		self.len = self.len - n
	end

	--slice interface

	--NOTE: j is not the last position, but one position after that!
	terra arr:range(i: size_t, j: size_t, truncate: bool)
		if i < 0 then i = self.len - i end
		if j < 0 then j = self.len - j end
		check(i >= 0)
		j = max(i, j)
		if truncate then j = min(self.len, j) end
		return i, j-i
	end

	terra arr:slice(i: size_t, j: size_t) --NOTE: aliasing!
		var start, len = self:range(i, j, true)
		return arr {self.data+i, -i, len}
	end

	--array-to-array interface

	terra arr:update(i: size_t, a: &arr)
		if i < 0 then i = self.len - i end; check(i >= 0)
		if a.len == 0 then return true end
		var newlen = max(self.len, i+a.len)
		if newlen > self.len then
			if not self:realloc(newlen) then return false end
			if i >= self.len + 1 then --clear the gap
				memset(self.data + self.len, 0, sizeof(T) * (i - self.len))
			end
			self.len = newlen
		end
		memmove(self.data+i, a.data, a.len)
		return true
	end

	terra arr:append(a: &arr)
		return self:update(self.len, a)
	end

	insert:adddefinition(
		terra(self: &arr, i: size_t, a: &arr)
			return self:insert(i, a.len) and self:update(i, a)
		end)

	--sorting and searching

	terra arr:find(val: T)
		for i,v in self do
			if v == val then
				return true
			end
		end
		return false
	end

	terra arr:sort(equal)
		--
	end

	terra:binsearch(val: T)
		--TODO
	end

	return arr
end

local dynarray_type = terralib.memoize(
	function(T, size_t, growth_factor, C)
		T = T or int32
		size_t = size_t or int32
		growth_factor = growth_factor or 2
		C = C or require'low'.C
		return dynarray_type(T, size_t, growth_factor, C)
	end)

local dynarray = macro(
	--calling it from Terra returns a new array.
	function(T, size_t, growth_factor)
		T = T and T:astype()
		size_t = size_t and size_t:astype()
		local arr = dynarray_type(T, size_t, growth_factor)
		return quote var a: arr = {} in a end
	end,
	--calling it from Lua or from an escape or in a type declaration returns
	--just the type, and you can also pass a custom C namespace.
	function(T, size_t, growth_factor, C)
		return dynarray_type(T, size_t, growth_factor, C)
	end
)

return dynarray
