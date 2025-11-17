PROJECT = "gpio_test"
VERSION = "1.0.0"

sys = require("sys")

-- 合宙Air780系列模块可用的GPIO引脚列表
-- 注意：具体可用GPIO可能因模块型号而异，请根据实际硬件调整
local available_gpios = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19,
    20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39,
    40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
    60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
    80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99
}

-- 当前GPIO索引
local current_gpio_index = 0
local current_gpio = nil

-- 日志输出函数
local function log_gpio(tag, message)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local log_str = string.format("[%s][%s] %s", timestamp, tag, tostring(message))
    log.info(log_str)
end

-- 初始化所有GPIO为输出模式，下拉电阻
local function init_all_gpios()
    log_gpio("INIT", "开始初始化所有GPIO引脚...")
    
    local success_count = 0
    local failed_gpios = {}
    
    for _, gpio_num in ipairs(available_gpios) do
        local success, result = pcall(gpio.setup, gpio_num, 0, gpio.PULLDOWN)
        if success then
            -- 初始化设置为低电平
            gpio.set(gpio_num, 0)
            success_count = success_count + 1
        else
            table.insert(failed_gpios, gpio_num)
            log_gpio("ERROR", string.format("GPIO %d 初始化失败: %s", gpio_num, tostring(result)))
        end
    end
    
    log_gpio("INIT", string.format("GPIO初始化完成 - 成功: %d个, 失败: %d个", success_count, #failed_gpios))
    if #failed_gpios > 0 then
        log_gpio("ERROR", "失败的GPIO列表: " .. table.concat(failed_gpios, ", "))
    end
    
    return success_count > 0
end

-- 测试单个GPIO引脚
local function test_gpio(gpio_num)
    if gpio_num == nil then
        return false
    end
    
    log_gpio("TEST", string.format("开始测试 GPIO %d", gpio_num))
    
    -- 尝试设置GPIO为高电平
    local success, result = pcall(gpio.set, gpio_num, 1)
    if not success then
        log_gpio("ERROR", string.format("GPIO %d 设置高电平失败: %s", gpio_num, tostring(result)))
        return false
    end
    
    log_gpio("TEST", string.format("GPIO %d 设置为高电平 ✓", gpio_num))
    
    -- 等待1秒
    sys.wait(1000)
    
    -- 设置为低电平
    local success, result = pcall(gpio.set, gpio_num, 0)
    if not success then
        log_gpio("ERROR", string.format("GPIO %d 设置低电平失败: %s", gpio_num, tostring(result)))
        return false
    end
    
    log_gpio("TEST", string.format("GPIO %d 设置为低电平 ✓", gpio_num))
    
    return true
end

-- 遍历测试所有GPIO
local function scan_all_gpios()
    log_gpio("SCAN", "开始遍历测试所有GPIO引脚...")
    
    for i, gpio_num in ipairs(available_gpios) do
        current_gpio_index = i
        current_gpio = gpio_num
        
        log_gpio("SCAN", string.format("测试进度: %d/%d, 当前GPIO: %d", i, #available_gpios, gpio_num))
        
        -- 测试当前GPIO
        local test_result = test_gpio(gpio_num)
        if test_result then
            log_gpio("SUCCESS", string.format("GPIO %d 测试成功", gpio_num))
        else
            log_gpio("FAILED", string.format("GPIO %d 测试失败", gpio_num))
        end
        
        -- 等待1秒再测试下一个
        sys.wait(1000)
    end
    
    log_gpio("SCAN", "所有GPIO测试完成！")
    log_gpio("INFO", "请检查您板子上的LED或设备变化，找出对应的GPIO编号")
end

-- 手动测试指定GPIO
local function manual_test_gpio(gpio_num)
    log_gpio("MANUAL", string.format("手动测试 GPIO %d", gpio_num))
    
    -- 设置为高电平并保持2秒
    log_gpio("MANUAL", string.format("GPIO %d 设置为高电平，请观察...", gpio_num))
    gpio.set(gpio_num, 1)
    sys.wait(2000)
    
    -- 设置为低电平
    log_gpio("MANUAL", string.format("GPIO %d 设置为低电平", gpio_num))
    gpio.set(gpio_num, 0)
    
    log_gpio("MANUAL", string.format("GPIO %d 手动测试完成", gpio_num))
end

-- 主测试任务
sys.taskInit(function()
    log_gpio("START", "GPIO测试程序启动")
    
    -- 等待系统稳定
    sys.wait(2000)
    
    -- 初始化所有GPIO
    if not init_all_gpios() then
        log_gpio("ERROR", "GPIO初始化失败，程序退出")
        return
    end
    
    -- 等待用户准备
    log_gpio("INFO", "5秒后开始自动遍历测试所有GPIO...")
    log_gpio("INFO", "请仔细观察板子上的LED或设备状态变化")
    log_gpio("INFO", "记录下对应变化的GPIO编号")
    
    sys.wait(5000)
    
    -- 开始遍历测试
    scan_all_gpios()
    
    -- 完成后进入手动测试模式
    log_gpio("MANUAL_MODE", "进入手动测试模式")
    log_gpio("MANUAL_MODE", "每5秒测试一个常用GPIO: 2, 26, 27, 30, 37, 38")
    
    local common_gpios = {2, 26, 27, 30, 37, 38}
    while true do
        for _, gpio_num in ipairs(common_gpios) do
            manual_test_gpio(gpio_num)
            sys.wait(3000)  -- 3秒间隔
        end
        sys.wait(2000)  -- 循环间隔2秒
    end
end)

-- 启动系统
sys.run()