#include "system.h"
#include "fpga_turn_feedback.h"

/* Both existing drivers select +/-500 dps, nominal 65.5 LSB/(degree/s).
 * No wheel geometry, tire traction, or motor command is used as yaw angle.
 */
#define TURN_GYRO_LSB_PER_DPS       65.5f
#define TURN_DEGREES_TO_RAD         0.017453292519943295f
#define TURN_FEEDBACK_MAX_AGE_TICKS M2T(100)
#define TURN_CALIBRATION_SAMPLES    200u
#define TURN_CALIBRATION_STD_DPS    0.75f
#define TURN_CALIBRATION_BIAS_DPS   20.0f
#define TURN_STATIONARY_SPEED_MPS   0.025f
#define TURN_MAX_GYRO_DPS           490.0f

static volatile float checked_yaw_rate;
static volatile uint32_t checked_sample_tick;
static volatile uint8_t checked_sample_valid;
static uint8_t bias_ready;
static uint16_t calibration_count;
static float calibration_mean;
static float calibration_m2;
static float gyro_z_bias;

/* The legacy ReadOneByte/ReadBuff helpers discard ACK failures. Keep the
 * checked transactions here so legacy telemetry remains independent.
 */
static int turn_read_registers(uint8_t address, uint8_t reg,
                               uint8_t *data, uint8_t length)
{
    uint8_t index;
    I2C_Start();
    I2C_WriteByte(address);
    if (!I2C_WaiteForAck()) goto failed;
    I2C_WriteByte(reg);
    if (!I2C_WaiteForAck()) goto failed;
    I2C_Start();
    I2C_WriteByte((uint8_t)(address | 1u));
    if (!I2C_WaiteForAck()) goto failed;
    for (index = 0; index < length; ++index)
        data[index] = I2C_ReadByte(index + 1u == length ? I2C_NACK : I2C_ACK);
    I2C_Stop();
    return 1;
failed:
    I2C_Stop();
    return 0;
}

static int turn_write_register(uint8_t address, uint8_t reg, uint8_t value)
{
    I2C_Start();
    I2C_WriteByte(address);
    if (!I2C_WaiteForAck()) goto failed;
    I2C_WriteByte(reg);
    if (!I2C_WaiteForAck()) goto failed;
    I2C_WriteByte(value);
    if (!I2C_WaiteForAck()) goto failed;
    I2C_Stop();
    return 1;
failed:
    I2C_Stop();
    return 0;
}

/* Enable raw-data-ready reporting and retain it until INT_STATUS is read.
 * Other enable/pin configuration bits are preserved. No MCU EXTI is enabled.
 */
static int turn_data_ready_config(uint8_t address, uint8_t pin_reg,
                                  uint8_t enable_reg)
{
    uint8_t value;
    if (!turn_read_registers(address, pin_reg, &value, 1u)) return 0;
    if ((value & 0x10u) != 0u &&
        !turn_write_register(address, pin_reg, (uint8_t)(value & ~0x10u)))
        return 0;
    if (!turn_read_registers(address, enable_reg, &value, 1u)) return 0;
    if ((value & 0x01u) == 0u &&
        !turn_write_register(address, enable_reg, (uint8_t)(value | 0x01u)))
        return 0;
    return 1;
}

/* 1 = fresh raw gyro sample; 0 = no new sample; -1 = invalid sensor/bus.
 * A single burst avoids combining the high/low bytes of different samples.
 */
static int turn_read_raw_gyro_z(int16_t *gyro_z)
{
    uint8_t id, config, status, bytes[6];
    if (SysVal.HardWare_Ver == V1_0)
    {
        if (!turn_read_registers(devAddr, MPU6050_RA_WHO_AM_I, &id, 1u) ||
            id != MPU6050_DEFAULT_ADDRESS) return -1;
        if (!turn_read_registers(devAddr, MPU6050_RA_GYRO_CONFIG, &config, 1u) ||
            (config & 0x18u) != 0x08u) return -1;
        if (!turn_read_registers(devAddr, MPU6050_RA_PWR_MGMT_1, &config, 1u) ||
            (config & 0x60u) != 0u) return -1;
        if (!turn_data_ready_config(devAddr, MPU6050_RA_INT_PIN_CFG,
                                    MPU6050_RA_INT_ENABLE)) return -1;
        if (!turn_read_registers(devAddr, MPU6050_RA_INT_STATUS, &status, 1u))
            return -1;
        if ((status & 0x01u) == 0u) return 0;
        if (!turn_read_registers(devAddr, MPU6050_RA_GYRO_XOUT_H, bytes, 6u))
            return -1;
    }
    else if (SysVal.HardWare_Ver == V1_1)
    {
        if (!turn_write_register(I2C_ADD_ICM20948, REG_ADD_REG_BANK_SEL,
                                 REG_VAL_REG_BANK_0)) return -1;
        if (!turn_read_registers(I2C_ADD_ICM20948, REG_ADD_WIA, &id, 1u) ||
            id != REG_VAL_WIA) return -1;
        if (!turn_read_registers(I2C_ADD_ICM20948, REG_ADD_PWR_MGMT_1,
                                 &config, 1u) || (config & 0x60u) != 0u)
            return -1;
        if (!turn_write_register(I2C_ADD_ICM20948, REG_ADD_REG_BANK_SEL,
                                 REG_VAL_REG_BANK_2)) return -1;
        if (!turn_read_registers(I2C_ADD_ICM20948, REG_ADD_GYRO_CONFIG_1,
                                 &config, 1u))
        {
            turn_write_register(I2C_ADD_ICM20948, REG_ADD_REG_BANK_SEL,
                                 REG_VAL_REG_BANK_0);
            return -1;
        }
        if (!turn_write_register(I2C_ADD_ICM20948, REG_ADD_REG_BANK_SEL,
                                 REG_VAL_REG_BANK_0)) return -1;
        if ((config & 0x06u) != REG_VAL_BIT_GYRO_FS_500DPS) return -1;
        /* ICM-20948 bank 0: INT_PIN_CFG=0x0f, INT_ENABLE_1=0x11,
         * INT_STATUS_1=0x1a; RAW_DATA_0_RDY is bit 0.
         */
        if (!turn_data_ready_config(I2C_ADD_ICM20948, 0x0fu, 0x11u)) return -1;
        if (!turn_read_registers(I2C_ADD_ICM20948, 0x1au, &status, 1u)) return -1;
        if ((status & 0x01u) == 0u) return 0;
        if (!turn_read_registers(I2C_ADD_ICM20948, REG_ADD_GYRO_XOUT_H,
                                 bytes, 6u)) return -1;
    }
    else return -1;

    *gyro_z = (int16_t)(((uint16_t)bytes[4] << 8) | bytes[5]);
    return 1;
}

static void turn_reset_calibration(void)
{
    calibration_count = 0u;
    calibration_mean = 0.0f;
    calibration_m2 = 0.0f;
}

static int turn_wheels_stationary(void)
{
    return fabsf(robot.MOTOR_A.Encoder) <= TURN_STATIONARY_SPEED_MPS &&
           fabsf(robot.MOTOR_B.Encoder) <= TURN_STATIONARY_SPEED_MPS &&
           fabsf(robot.MOTOR_C.Encoder) <= TURN_STATIONARY_SPEED_MPS &&
           fabsf(robot.MOTOR_D.Encoder) <= TURN_STATIONARY_SPEED_MPS;
}

void FPGA_TurnFeedbackSample(void)
{
    int16_t raw_z;
    int result = turn_read_raw_gyro_z(&raw_z);
    float raw, delta, variance_limit, rate;
    if (result < 0)
    {
        checked_sample_valid = 0u;
        if (!bias_ready) turn_reset_calibration();
        return;
    }
    if (result == 0) return;
    raw = (float)raw_z;

    /* Calibrate only during the existing stationary ten-second startup.
     * The checked raw register value bypasses both legacy ICM offsets.
     * Movement or excessive bias resets this startup-only estimate.
     */
    if (SysVal.Time_count < CONTROL_DELAY)
    {
        checked_sample_valid = 0u;
        if (!turn_wheels_stationary() ||
            fabsf(raw) > TURN_CALIBRATION_BIAS_DPS * TURN_GYRO_LSB_PER_DPS)
        {
            turn_reset_calibration();
            return;
        }
        if (calibration_count < 1000u)
        {
            ++calibration_count;
            delta = raw - calibration_mean;
            calibration_mean += delta / (float)calibration_count;
            calibration_m2 += delta * (raw - calibration_mean);
        }
        return;
    }
    if (!bias_ready)
    {
        variance_limit = TURN_CALIBRATION_STD_DPS * TURN_GYRO_LSB_PER_DPS;
        variance_limit *= variance_limit;
        if (calibration_count < TURN_CALIBRATION_SAMPLES ||
            calibration_m2 / (float)(calibration_count - 1u) > variance_limit ||
            !turn_wheels_stationary())
        {
            checked_sample_valid = 0u;
            return;
        }
        gyro_z_bias = calibration_mean;
        bias_ready = 1u;
    }

    rate = (raw - gyro_z_bias) / TURN_GYRO_LSB_PER_DPS;
    if (fabsf(raw) >= TURN_MAX_GYRO_DPS * TURN_GYRO_LSB_PER_DPS ||
        fabsf(rate) >= TURN_MAX_GYRO_DPS)
    {
        checked_sample_valid = 0u;
        return;
    }
    /* The balance task has higher priority than the IMU task. Publish the
     * rate, timestamp, and validity together to avoid a mixed snapshot.
     */
    taskENTER_CRITICAL();
    checked_yaw_rate = rate * TURN_DEGREES_TO_RAD;
    checked_sample_tick = getSysTickCnt();
    checked_sample_valid = 1u;
    taskEXIT_CRITICAL();
}

int FPGA_TurnReadYawRate(float *rate_rad_s)
{
    uint8_t valid;
    uint32_t sample_tick;
    float rate;
    if (rate_rad_s == NULL) return 0;
    taskENTER_CRITICAL();
    valid = checked_sample_valid;
    sample_tick = checked_sample_tick;
    rate = checked_yaw_rate;
    taskEXIT_CRITICAL();
    if (!valid || (uint32_t)(getSysTickCnt() - sample_tick) >
                  TURN_FEEDBACK_MAX_AGE_TICKS)
        return 0;
    *rate_rad_s = rate;
    return 1;
}
