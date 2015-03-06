
local function probit(x)
    local function inverseError(x)
        local a = 0.147

        if x == 0 then
            return 0
        end

        local log = math.log(1 - x * x)
        local log_div_2 = log / 2
        local b = log_div_2 + 2 / math.pi/ a
        local first_root = math.sqrt(b * b - log / 2)
        local second_root = math.sqrt(first_root - b)

        if x > 0 then
            return second_root
        end

        return -1 * second_root
    end

    return (inverseError(x * 2 - 1) * math.sqrt(2))
end

print(probit(0.5))
print(probit(0.99999))
print(probit(1 - 0.99999))

