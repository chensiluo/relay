-- 继电器控制系统配置文件
-- 包含硬件引脚配置和MQTT配置

-- ============================================================================
-- 硬件引脚配置
-- ============================================================================

-- LED指示灯配置
local LED_RX_GPIO = 26                -- 接收指示灯GPIO，高电平点亮（收到MQTT消息时闪烁）
local LED_TX_GPIO = 27                -- 发送指示灯GPIO，高电平点亮（发送MQTT消息时闪烁）

-- 继电器控制引脚配置：高电平开启
local RELAY_GPIO_1 = 2               -- 继电器1控制GPIO
local RELAY_GPIO_2 = 24              -- 继电器2控制GPIO  
local RELAY_GPIO_3 = 38              -- 继电器3控制GPIO
local RELAY_GPIO_4 = 37              -- 继电器4控制GPIO

-- ============================================================================
-- MQTT配置
-- ============================================================================

local def_cfg = {
    mqtt_host = "o6ca3537.ala.cn-hangzhou.emqxsl.cn",
    mqtt_port = 8883,
    mqtt_ssl = true,
    mqtt_user = "super-sms",
    mqtt_pwd = "super-sms",
}

-- ============================================================================
-- 导出配置
-- ============================================================================

return {
    -- 硬件引脚配置
    LED_RX_GPIO = LED_RX_GPIO,
    LED_TX_GPIO = LED_TX_GPIO,
    RELAY_GPIO_1 = RELAY_GPIO_1,
    RELAY_GPIO_2 = RELAY_GPIO_2,
    RELAY_GPIO_3 = RELAY_GPIO_3,
    RELAY_GPIO_4 = RELAY_GPIO_4,
    
    -- MQTT配置
    mqtt_config = def_cfg
}