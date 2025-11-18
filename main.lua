PROJECT = "relay_control"
VERSION = "1.0.0"

sys = require("sys")
conf = require("main_config")

-- 从配置文件加载硬件引脚配置
local LED_RX_GPIO = conf.LED_RX_GPIO
local LED_TX_GPIO = conf.LED_TX_GPIO
local RELAY_GPIO_1 = conf.RELAY_GPIO_1
local RELAY_GPIO_2 = conf.RELAY_GPIO_2
local RELAY_GPIO_3 = conf.RELAY_GPIO_3
local RELAY_GPIO_4 = conf.RELAY_GPIO_4


-- 从配置文件加载MQTT配置
local cur_cfg = conf.mqtt_config

-- 日志函数 - 移到文件开头，避免nil错误
local function log_msg(tag, message)
    local log_str = string.format("[%s] %s", tag, tostring(message))
    -- 输出到串口
    log.info(log_str)
end

-- GPIO状态存储键名
local GPIO_STATUS_KEY = "gpio_status"

-- 初始化KV数据库（程序启动时执行一次）
if not fskv.init() then
    log_msg("KV", "KV数据库初始化失败")
    error("KV数据库初始化失败，程序无法继续运行")
end
log_msg("KV", "KV数据库初始化成功")

-- 保存GPIO状态到KV数据库
local function save_gpio_status(gpio_num, state)
    
    -- 获取当前所有GPIO状态
    local gpio_status = fskv.get(GPIO_STATUS_KEY) or {}
    
    -- 更新指定GPIO的状态
    gpio_status[tostring(gpio_num)] = state and 1 or 0
    
    -- 保存回KV数据库
    local success = fskv.set(GPIO_STATUS_KEY, gpio_status)
    if success then
        log_msg("KV", string.format("GPIO %d状态已保存: %s", gpio_num, state and "高电平" or "低电平"))
    else
        log_msg("KV", string.format("GPIO %d状态保存失败", gpio_num))
    end
    
    return success
end

-- 从KV数据库加载GPIO状态
local function load_gpio_status()
    
    local gpio_status = fskv.get(GPIO_STATUS_KEY)
    if gpio_status then
        log_msg("KV", "GPIO状态已从KV数据库加载")
        log_msg("KV", "保存的GPIO状态: " .. json.encode(gpio_status))
    else
        log_msg("KV", "未找到保存的GPIO状态，使用默认状态")
        gpio_status = {}
    end
    
    return gpio_status
end

-- 恢复GPIO状态
local function restore_gpio_states()
    local saved_states = load_gpio_status()
    
    -- 恢复继电器GPIO状态
    local relay_gpios = {RELAY_GPIO_1, RELAY_GPIO_2, RELAY_GPIO_3, RELAY_GPIO_4}
    for _, gpio_num in ipairs(relay_gpios) do
        local saved_state = saved_states[tostring(gpio_num)]
        if saved_state ~= nil then
            -- 设置GPIO状态
            local state = (saved_state == 1)
            gpio.set(gpio_num, state and gpio.HIGH or gpio.LOW)
            log_msg("GPIO", string.format("恢复GPIO %d状态: %s", gpio_num, state and "高电平" or "低电平"))
        end
    end
    
    log_msg("GPIO", "所有GPIO状态恢复完成")
end
-- 全局变量
local mqtt_client = nil
local imei = mobile.imei()
local sub_topic = imei.."/sub"       -- 设备订阅主题，前端发布命令
local pub_topic = imei.."/pub"       -- 设备发布主题，设备发布GPIO状态
local status_topic = imei.."/status" -- 设备状态主题，用于定时发送心跳



-- LED闪烁函数
local function flash_led(gpio_num, duration)
    gpio.set(gpio_num, gpio.HIGH)
    sys.timerStart(function()
        gpio.set(gpio_num, gpio.LOW)
    end, duration or 200)
end

-- 初始化GPIO
local function init_gpio()
    -- 初始化LED为输出模式
    gpio.setup(LED_RX_GPIO, 0, gpio.PULLDOWN)
    gpio.setup(LED_TX_GPIO, 0, gpio.PULLDOWN)
    
    -- 初始化继电器控制引脚为输出模式，默认低电平
    gpio.setup(RELAY_GPIO_1, 0, gpio.PULLDOWN)
    gpio.setup(RELAY_GPIO_2, 0, gpio.PULLDOWN)
    gpio.setup(RELAY_GPIO_3, 0, gpio.PULLDOWN)
    gpio.setup(RELAY_GPIO_4, 0, gpio.PULLDOWN)
    
    log_msg("GPIO", "所有GPIO初始化完成")
    
    -- 恢复保存的GPIO状态
    restore_gpio_states()
end


-- 获取设备状态
local function get_device_status()
    -- 获取GPIO电平状态（高电平为1，低电平为0）
    -- 高电平gpio.HIGH, 低电平gpio.LOW, 对应数值1和0
    local gpio1_state = gpio.get(RELAY_GPIO_1) == gpio.HIGH and 1 or 0
    local gpio2_state = gpio.get(RELAY_GPIO_2) == gpio.HIGH and 1 or 0
    local gpio3_state = gpio.get(RELAY_GPIO_3) == gpio.HIGH and 1 or 0
    local gpio4_state = gpio.get(RELAY_GPIO_4) == gpio.HIGH and 1 or 0
    
    return {
        -- 使用gpio前缀的字段名来适配前端
        ["gpio"..RELAY_GPIO_1] = gpio1_state,
        ["gpio"..RELAY_GPIO_2] = gpio2_state,
        ["gpio"..RELAY_GPIO_3] = gpio3_state,
        ["gpio"..RELAY_GPIO_4] = gpio4_state,
        -- 信号强度
        csq = mobile.csq() or 0,
    }
end

-- 发送完整设备状态
local function send_device_status()
    if not mqtt_client then
        log_msg("STATUS", "MQTT客户端未初始化，无法发送状态")
        return false
    end
    
    if not mqtt_client:ready() then
        log_msg("STATUS", "MQTT连接未就绪，无法发送状态")
        return false
    end
    
    local status_data = get_device_status()
    log_msg("STATUS", "准备发送状态数据: "..json.encode(status_data))
    
    -- status_data.type = "status_update"
    local publish_result = mqtt_client:publish(pub_topic, json.encode(status_data))
    
    if publish_result then
        -- 发送消息时闪烁TX LED
        flash_led(LED_TX_GPIO, 200)
        log_msg("STATUS", "设备状态发送成功")
        return true
    else
        log_msg("STATUS", "设备状态发送失败")
        return false
    end
end

-- MQTT命令处理
local function handle_mqtt_command(payload)
    -- 收到消息时闪烁RX LED
    flash_led(LED_RX_GPIO, 200)
    
    local success, data = pcall(json.decode, payload)
    if not success then
        log_msg("MQTT", "无效的JSON格式: "..payload)
        return json.encode({
            result = "error",
            message = "invalid json format"
        })
    end
    
    -- 处理重启命令
    if data.command == "reboot" then
        log_msg("MQTT", "收到重启设备命令")
        
        -- 发送响应，表示命令已接收
        local response = json.encode({
            result = "success",
            message = "设备即将重启"
        })
        
        -- 延迟执行重启，确保响应能够发送
        sys.timerStart(function()
            log_msg("SYSTEM", "设备正在重启...")
            pm.reboot()
        end, 1000)  -- 1秒后重启
        
        return response
    
    
    -- 处理继电器控制命令：{"gpio": 37, "action": "open"}
    elseif data.gpio and data.action then
        local gpio_num = tonumber(data.gpio)
        local action = tostring(data.action):lower()
        
        log_msg("MQTT", "收到GPIO控制命令: gpio="..gpio_num..", action="..action)
        
        -- 验证GPIO编号
        local valid_gpios = {RELAY_GPIO_1, RELAY_GPIO_2, RELAY_GPIO_3, RELAY_GPIO_4}
        local valid = false
        for _, v in ipairs(valid_gpios) do
            if gpio_num == v then
                valid = true
                break
            end
        end
        
        if not valid then
            log_msg("MQTT", "无效的GPIO编号: "..gpio_num)
            return json.encode({
                result = "error",
                message = "invalid gpio number"
            })
        end
        
        -- 处理开启/关闭操作
        if action == "open" then
            -- 开启GPIO（拉高电平）
            gpio.set(gpio_num, 1)
            log_msg("GPIO", "GPIO开启成功: "..gpio_num)
            
            -- 保存GPIO状态到KV数据库
            save_gpio_status(gpio_num, true)
            
            -- 控制成功后发送状态更新
            send_device_status()
            return json.encode({
                result = "success",
                gpio = gpio_num,
                action = "open",
                message = "GPIO开启成功"
            })
        elseif action == "close" then
            -- 关闭GPIO（拉低电平）
            gpio.set(gpio_num, 0)
            log_msg("GPIO", "GPIO关闭成功: "..gpio_num)
            
            -- 保存GPIO状态到KV数据库
            save_gpio_status(gpio_num, false)
            
            -- 控制成功后发送状态更新
            send_device_status()
            return json.encode({
                result = "success",
                gpio = gpio_num,
                action = "close",
                message = "GPIO关闭成功"
            })
        else
            log_msg("MQTT", "无效的操作类型: "..action)
            return json.encode({
                result = "error",
                message = "action must be 'open' or 'close'"
            })
        end
    else
        log_msg("MQTT", "无效的命令格式: "..payload)
        return json.encode({
            result = "error",
            message = "invalid command format, expected {\"gpio\": number, \"action\": \"open\" or \"close\"} or {\"command\": \"update_config\", \"config\": {...}}"
        })
    end
end

-- MQTT客户端初始化
local function init_mqtt()
    -- 输出连接信息
    log_msg("MQTT", "开始初始化MQTT客户端...")
    log_msg("MQTT", "MQTT服务器: "..cur_cfg.mqtt_host)
    log_msg("MQTT", "MQTT端口: "..cur_cfg.mqtt_port)
    log_msg("MQTT", "MQTT SSL: "..(cur_cfg.mqtt_ssl and "启用" or "禁用"))
    log_msg("MQTT", "MQTT用户名: "..cur_cfg.mqtt_user)
    log_msg("MQTT", "设备IMEI: "..imei)
    
    if not (cur_cfg.mqtt_host and cur_cfg.mqtt_port) then
        log_msg("MQTT", "MQTT配置错误: 地址或端口未设置")
        return
    end
    
    local mqttc = mqtt.create(nil, cur_cfg.mqtt_host, cur_cfg.mqtt_port, cur_cfg.mqtt_ssl)
    if not mqttc then
        log_msg("MQTT", "MQTT客户端创建失败")
        return
    end
    
    log_msg("MQTT", "MQTT客户端创建成功，开始配置...")
    
    -- 认证配置
    mqttc:auth(imei, cur_cfg.mqtt_user, cur_cfg.mqtt_pwd)
    mqttc:autoreconn(true, 3000)  -- 自动重连，3秒间隔
    
    log_msg("MQTT", "MQTT认证配置完成，设置回调函数...")
    
    -- 回调处理
    mqttc:on(function(client, event, data, payload)
        if event == "conack" then
            -- 连接成功
            log_msg("MQTT", "MQTT连接成功！连接确认收到")
            log_msg("MQTT", "开始订阅主题: "..sub_topic)
            
            -- 订阅前端命令主题
            local subscribe_result = client:subscribe(sub_topic)
            if subscribe_result then
                log_msg("MQTT", "主题订阅成功: "..sub_topic)
            else
                log_msg("MQTT", "主题订阅失败: "..sub_topic)
            end
            
            -- 发送设备上线通知
            log_msg("MQTT", "发送设备上线通知...")
            send_device_status()
            
        elseif event == "recv" then
            -- 收到控制命令
            log_msg("MQTT", "收到命令: "..payload)
            local result = handle_mqtt_command(payload)
            log_msg("MQTT", "命令处理结果: "..result)
            
            -- 将命令处理结果发布到/pub主题
            if result and client:ready() then
                local publish_result = client:publish(pub_topic, result)
                if publish_result then
                    log_msg("MQTT", "命令结果已发布到/pub主题")
                else
                    log_msg("MQTT", "命令结果发布失败")
                end
            end
            
        elseif event == "disconnect" then
            log_msg("MQTT", "MQTT连接断开，将自动重连...")
            
        elseif event == "sent" then
            log_msg("MQTT", "消息发送成功")
            
        else
            log_msg("MQTT", "未知的MQTT事件: "..tostring(event))
        end
    end)
    
    log_msg("MQTT", "开始连接MQTT服务器...")
    -- 开始连接
    if not mqttc:connect() then
        log_msg("MQTT", "MQTT连接发起失败 - 检查服务器地址和端口")
        log_msg("MQTT", "请检查网络连接和服务器状态")
        mqttc:close()
        return
    else
        log_msg("MQTT", "MQTT连接请求已发送，等待服务器响应...")
    end
    
    return mqttc
end

-- 主任务：设备初始化
sys.taskInit(function()
    log_msg("SYSTEM", "设备启动中...")
    log_msg("SYSTEM", "IMEI: "..imei)
    
    -- 等待网络就绪
    log_msg("SYSTEM", "等待网络就绪...")
    sys.waitUntil("IP_READY")
    log_msg("SYSTEM", "网络已就绪")
    sys.wait(3000)
    
    -- 检查网络状态
    local csq = mobile.csq()
    local iccid = mobile.iccid()
    log_msg("SYSTEM", "信号强度: "..(csq or "未知"))
    log_msg("SYSTEM", "SIM卡ICCID: "..(iccid or "未知"))
    
    -- 初始化GPIO
    log_msg("SYSTEM", "初始化GPIO...")
    init_gpio()
    
    -- 初始化MQTT
    log_msg("SYSTEM", "初始化MQTT客户端...")
    mqtt_client = init_mqtt()
    
    if mqtt_client then
        log_msg("SYSTEM", "MQTT客户端初始化成功")
    else
        log_msg("SYSTEM", "MQTT客户端初始化失败")
    end
    log_msg("SYSTEM", "设备启动完成，开始运行")

end)

-- 定时发送设备状态和心跳（每5秒一次）
sys.taskInit(function()
    log_msg("SYSTEM", "启动MQTT状态监控任务...")
    
    -- 等待MQTT客户端就绪
    local wait_count = 0
    while true do
        if mqtt_client then
            if mqtt_client:ready() then
                log_msg("SYSTEM", "MQTT客户端已就绪，开始定时发送状态")
                break
            else
                wait_count = wait_count + 1
                if wait_count % 10 == 1 then  -- 每10秒输出一次等待信息
                    log_msg("SYSTEM", "等待MQTT连接就绪... ("..wait_count.."秒)")
                end
            end
        else
            log_msg("SYSTEM", "MQTT客户端未初始化，等待...")
        end
        sys.wait(3000)
    end
    
    log_msg("SYSTEM", "开始定时发送设备状态和心跳...")
    
    -- 启动5秒定时发送状态和心跳
    while true do
        -- 检查MQTT连接状态
        if mqtt_client and mqtt_client:ready() then
            -- 发送设备状态到pub主题
            send_device_status()
        else
            log_msg("SYSTEM", "MQTT连接异常，尝试重新初始化...")
            mqtt_client = init_mqtt()
        end
        
        sys.wait(30000)  -- 每30秒发送一次
    end
end)

-- 心跳定时任务（每1秒发送一个点）
sys.taskInit(function()
    log_msg("SYSTEM", "开始定时发送心跳...")
    -- 启动2秒定时发送心跳
    while true do
        -- 检查MQTT连接状态
        if mqtt_client and mqtt_client:ready() then
            -- 发送心跳到status主题
            mqtt_client:publish(status_topic, ".")
        end
        
        sys.wait(2000)  -- 每2秒发送一次
    end
end)

-- 启动系统
sys.run()