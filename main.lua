PROJECT = "relay_control"
VERSION = "1.0.0"

sys = require("sys")

-- 硬件引脚配置
local LED_RX_GPIO = 26                -- 接收指示灯GPIO，高电平点亮（收到MQTT消息时闪烁）
local LED_TX_GPIO = 27                -- 发送指示灯GPIO，高电平点亮（发送MQTT消息时闪烁）
local RELAY_GPIO_1 = 2               -- 继电器1控制GPIO，高电平开启
local RELAY_GPIO_2 = 30              -- 继电器2控制GPIO，高电平开启  
local RELAY_GPIO_3 = 38              -- 继电器3控制GPIO，高电平开启
local RELAY_GPIO_4 = 37               -- 继电器4控制GPIO，高电平开启

-- 全局变量
local mqtt_client = nil
local imei = mobile.imei()
local sub_topic = imei.."/sub"       -- 设备订阅主题，前端发布命令
local pub_topic = imei.."/pub"       -- 设备发布主题，设备发布GPIO状态
local status_topic = imei.."/status" -- 设备心跳主题

-- 默认配置
local def_cfg = {
    mqtt_host = "120.25.229.70",
    mqtt_port = 1883,
    mqtt_ssl = false,
    mqtt_user = "super-sms",
    mqtt_pwd = "super-sms",
}

-- 加载配置
local function load_cfg()
    if not fskv.init() then
        log.error("kv", "初始化KV数据库失败")
        return def_cfg
    end
    
    local cur_cfg = fskv.get("relay_config")
    if not cur_cfg then
        fskv.set("relay_config", def_cfg)
        return def_cfg
    end
    return cur_cfg
end

local cur_cfg = load_cfg()

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
    gpio.setup(LED_RX_GPIO, gpio.OUTPUT, gpio.PULLUP)
    gpio.setup(LED_TX_GPIO, gpio.OUTPUT, gpio.PULLUP)
    
    -- 初始化继电器控制引脚为输出模式
    gpio.setup(RELAY_GPIO_1, gpio.OUTPUT, gpio.PULLUP)
    gpio.setup(RELAY_GPIO_2, gpio.OUTPUT, gpio.PULLUP)
    gpio.setup(RELAY_GPIO_3, gpio.OUTPUT, gpio.PULLUP)
    gpio.setup(RELAY_GPIO_4, gpio.OUTPUT, gpio.PULLUP)
    

    -- 初始化LED为熄灭状态
    gpio.set(LED_RX_GPIO, gpio.LOW)
    gpio.set(LED_TX_GPIO, gpio.LOW)
    
    log.info("GPIO", "所有GPIO初始化完成")
end


-- 获取设备状态
local function get_device_status()
    -- 获取GPIO电平状态（高电平为1，低电平为0）
    local gpio2_state = gpio.get(RELAY_GPIO_1) == gpio.HIGH and 1 or 0
    local gpio30_state = gpio.get(RELAY_GPIO_2) == gpio.HIGH and 1 or 0
    local gpio38_state = gpio.get(RELAY_GPIO_3) == gpio.HIGH and 1 or 0
    local gpio37_state = gpio.get(RELAY_GPIO_4) == gpio.HIGH and 1 or 0
    
    return {
        -- device_id = imei,
        -- timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        -- GPIO编号格式
        gpio2 = gpio2_state,
        gpio30 = gpio30_state,
        gpio38 = gpio38_state,
        gpio37 = gpio37_state,
        -- 信号强度
        csq = mobile.csq() or 0,
    }
end

-- 发送完整设备状态
local function send_device_status()
    if mqtt_client and mqtt_client:ready() then
        local status_data = get_device_status()
        -- status_data.type = "status_update"
        mqtt_client:publish(pub_topic, json.encode(status_data))
        
        -- 发送消息时闪烁TX LED
        flash_led(LED_TX_GPIO, 200)
        log.info("STATUS", "设备状态已发送")
    end
end

-- 日志函数
local function log_msg(tag, message)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local log_str = string.format("[%s][%s] %s", timestamp, tag, tostring(message))
    
    -- 输出到串口
    log.info(log_str)
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
    if data.command == "repboot" then
        log_msg("MQTT", "收到重启设备命令")
        
        -- 发送响应，表示命令已接收
        local response = json.encode({
            result = "success",
            message = "设备即将重启"
        })
        
        -- 延迟执行重启，确保响应能够发送
        sys.timerStart(function()
            log_msg("SYSTEM", "设备正在重启...")
            rtos.reboot()
        end, 1000)  -- 1秒后重启
        
        return response
    
    -- 处理配置更新命令
    elseif data.command == "update_config" and data.config then
        log_msg("MQTT", "收到配置更新命令")
        
        -- 验证配置数据
        local config = data.config
        if not config.mqtt_host or not config.mqtt_port then
            log_msg("MQTT", "配置数据不完整")
            return json.encode({
                result = "error",
                message = "配置数据不完整，需要mqtt_host和mqtt_port"
            })
        end
        
        -- 更新配置
        local new_config = {
            mqtt_host = tostring(config.mqtt_host),
            mqtt_port = tonumber(config.mqtt_port),
            mqtt_user = tostring(config.mqtt_user or def_cfg.mqtt_user),
            mqtt_pwd = tostring(config.mqtt_pwd or def_cfg.mqtt_pwd),
            mqtt_ssl = config.mqtt_ssl and true or false
        }
        
        -- 保存配置到KV存储
        if fskv.init() then
            fskv.set("relay_config", new_config)
            log_msg("MQTT", "配置已保存到KV存储")
            
            -- 更新当前配置
            cur_cfg = new_config
            
            -- 发送响应
            return json.encode({
                result = "success",
                message = "配置更新成功，请手动重启设备"
            })
        else
            log_msg("MQTT", "KV存储初始化失败")
            return json.encode({
                result = "error",
                message = "配置保存失败"
            })
        end
    
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
    if not (cur_cfg.mqtt_host and cur_cfg.mqtt_port) then
        log_msg("MQTT", "MQTT配置错误: 地址或端口未设置")
        return
    end
    
    local mqttc = mqtt.create(nil, cur_cfg.mqtt_host, cur_cfg.mqtt_port, cur_cfg.mqtt_ssl)
    if not mqttc then
        log_msg("MQTT", "MQTT客户端创建失败")
        return
    end
    
    -- 认证配置
    mqttc:auth(imei, cur_cfg.mqtt_user, cur_cfg.mqtt_pwd)
    mqttc:autoreconn(true, 3000)  -- 自动重连，3秒间隔
    
    -- 回调处理
    mqttc:on(function(client, event, data, payload)
        if event == "conack" then
            -- 连接成功，订阅前端命令主题
            client:subscribe(sub_topic)
            log_msg("MQTT", "连接成功并订阅主题: "..sub_topic)
            
            -- 发送设备上线通知
            send_device_status()
            
        elseif event == "recv" then
            -- 收到控制命令
            log_msg("MQTT", "收到命令: "..payload)
            local result = handle_mqtt_command(payload)
            log_msg("MQTT", "命令处理结果: "..result)
            
        elseif event == "disconnect" then
            log_msg("MQTT", "MQTT连接断开")
        end
    end)
    
    -- 开始连接
    if not mqttc:connect() then
        log_msg("MQTT", "MQTT连接发起失败")
        mqttc:close()
        return
    end
    
    return mqttc
end

-- 主任务：设备初始化
sys.taskInit(function()
    -- 等待网络就绪
    sys.waitUntil("IP_READY")
    sys.wait(3000)
    
    -- 初始化GPIO
    init_gpio()
    
    -- 初始化MQTT
    mqtt_client = init_mqtt()
    
    -- 发送启动通知
    log_msg("SYSTEM", "设备启动完成，IMEI: "..imei)
    
    if mqtt_client and mqtt_client:ready() then
        mqtt_client:publish(status_topic, json.encode({
            device_id = imei,
            status = "online",
            timestamp = os.date("%Y-%m-%d %H:%M:%S"),
            message = "设备已上线"
        }))
    end
end)

-- 定时发送设备状态和心跳（每5秒一次）
sys.taskInit(function()
    -- 等待MQTT客户端就绪
    while true do
        if mqtt_client and mqtt_client.ready then
            break
        end
        sys.wait(1000)
    end
    
    -- 启动5秒定时发送状态和心跳
    while true do
        -- 发送设备状态到pub主题
        send_device_status()
        sys.wait(5000)  -- 每5秒发送一次
    end
end)

-- 启动系统
sys.run()