/* Compile and call the actual adapter; only platform/I2C dependencies are mocked.
 * Each invocation is a new process so production static calibration state is
 * initialized naturally, without test-only reset hooks in the firmware.
 */
#include "system.h"
#include "fpga_turn_feedback.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

FeedbackTestSys SysVal;
FeedbackTestRobot robot;
static uint32_t ticks;
static uint8_t registers[4][256];
static unsigned bank, bus_stage, register_pointer, last_write, read_mode;
static unsigned ack_count, nack_at, stops, read_count, burst_count, critical_depth;
static unsigned checks;

uint32_t getSysTickCnt(void) { return ticks; }
void feedback_test_enter_critical(void) { ++critical_depth; }
void feedback_test_exit_critical(void) { assert(critical_depth); --critical_depth; }

void I2C_Start(void) { bus_stage = 0; }
void I2C_Stop(void) { ++stops; bus_stage = 0; }
void I2C_WriteByte(uint8_t value)
{
    last_write = value;
    if (bus_stage == 0) {
        assert((value & 0xfeu) == 0xd0u);
        read_mode = value & 1u;
        bus_stage = 1;
    } else if (bus_stage == 1) {
        assert(!read_mode);
        register_pointer = value;
        bus_stage = 2;
    } else {
        assert(!read_mode);
        if (SysVal.HardWare_Ver == V1_1 && register_pointer == REG_ADD_REG_BANK_SEL)
            bank = (value >> 4) & 3u;
        else registers[bank][register_pointer++] = value;
    }
}
uint8_t I2C_WaiteForAck(void)
{
    (void)last_write;
    ++ack_count;
    return (uint8_t)(nack_at == 0 || ack_count != nack_at);
}
uint8_t I2C_ReadByte(uint8_t ack)
{
    uint8_t result;
    unsigned reg = register_pointer++;
    unsigned gyro = SysVal.HardWare_Ver == V1_0 ? MPU6050_RA_GYRO_XOUT_H : REG_ADD_GYRO_XOUT_H;
    unsigned status = SysVal.HardWare_Ver == V1_0 ? MPU6050_RA_INT_STATUS : 0x1a;
    assert(read_mode);
    if (bank == 0 && reg >= gyro && reg < gyro + 6u) {
        assert(ack == (reg == gyro + 5u ? I2C_NACK : I2C_ACK));
        if (reg == gyro + 5u) ++burst_count;
    } else assert(ack == I2C_NACK);
    result = registers[bank][reg];
    if (bank == 0 && reg == status) registers[bank][reg] &= (uint8_t)~1u;
    ++read_count;
    return result;
}
static void require(int condition) { ++checks; assert(condition); }
static void close_rate(float actual, float expected)
{
    require(fabsf(actual - expected) < 0.00005f);
}
static void set_raw(int16_t raw, int ready)
{
    unsigned gyro = SysVal.HardWare_Ver == V1_0 ? MPU6050_RA_GYRO_XOUT_H : REG_ADD_GYRO_XOUT_H;
    unsigned status = SysVal.HardWare_Ver == V1_0 ? MPU6050_RA_INT_STATUS : 0x1a;
    registers[0][gyro + 4u] = (uint8_t)((uint16_t)raw >> 8);
    registers[0][gyro + 5u] = (uint8_t)raw;
    registers[0][status] = ready ? 1u : 0u;
}
static void sample(int16_t raw, int ready)
{
    set_raw(raw, ready);
    ack_count = 0;
    FPGA_TurnFeedbackSample();
    require(critical_depth == 0);
}
static void initialize(unsigned model)
{
    memset(registers, 0, sizeof(registers));
    SysVal.HardWare_Ver = model == 0 ? V1_0 : V1_1;
    if (model == 0) {
        registers[0][MPU6050_RA_WHO_AM_I] = MPU6050_DEFAULT_ADDRESS;
        registers[0][MPU6050_RA_GYRO_CONFIG] = 0x08;
        registers[0][MPU6050_RA_INT_PIN_CFG] = 0xf0;
        registers[0][MPU6050_RA_INT_ENABLE] = 0xa0;
    } else {
        registers[0][REG_ADD_WIA] = REG_VAL_WIA;
        registers[2][REG_ADD_GYRO_CONFIG_1] = REG_VAL_BIT_GYRO_FS_500DPS;
        registers[0][0x0f] = 0xf0;
        registers[0][0x11] = 0xa0;
    }
}
static void calibrate(unsigned count, int variation)
{
    unsigned i;
    float rate = 8.0f;
    for (i = 0; i < count; ++i) {
        SysVal.Time_count = i < CONTROL_DELAY ? i : CONTROL_DELAY - 1u;
        ticks += 20;
        sample((int16_t)(131 + (variation ? ((i & 1u) ? 300 : -300) : 0)), 1);
        require(!FPGA_TurnReadYawRate(&rate));
    }
    SysVal.Time_count = CONTROL_DELAY;
}
static void healthy(void)
{
    float rate;
    unsigned pin = SysVal.HardWare_Ver == V1_0 ? MPU6050_RA_INT_PIN_CFG : 0x0f;
    unsigned enable = SysVal.HardWare_Ver == V1_0 ? MPU6050_RA_INT_ENABLE : 0x11;
    calibrate(200, 0);
    sample(131, 1);
    require(FPGA_TurnReadYawRate(&rate)); close_rate(rate, 0.0f);
    require(registers[0][pin] == 0xe0 && registers[0][enable] == 0xa1);
    require(bank == 0);
    sample(6681, 1);
    require(FPGA_TurnReadYawRate(&rate)); close_rate(rate, 1.745329252f);
    sample(-6419, 1);
    require(FPGA_TurnReadYawRate(&rate)); close_rate(rate, -1.745329252f);
    require(burst_count == 203);
    require(!FPGA_TurnReadYawRate(NULL));
}
int main(int argc, char **argv)
{
    unsigned model;
    const char *scenario;
    float rate = 8.0f;
    assert(argc >= 3);
    model = (unsigned)atoi(argv[1]); scenario = argv[2];
    initialize(model);
    if (!strcmp(scenario, "healthy")) healthy();
    else if (!strcmp(scenario, "insufficient")) {
        calibrate(199, 0); sample(131, 1); require(!FPGA_TurnReadYawRate(&rate));
    } else if (!strcmp(scenario, "no_drdy_calibration")) {
        unsigned i;
        for (i=0; i<200; ++i) { sample(131, 0); ++SysVal.Time_count; }
        SysVal.Time_count = CONTROL_DELAY; sample(131, 1);
        require(!FPGA_TurnReadYawRate(&rate)); require(burst_count == 1);
    } else if (!strcmp(scenario, "freshness")) {
        calibrate(200, 0); sample(6681, 1);
        ticks += 100; require(FPGA_TurnReadYawRate(&rate)); close_rate(rate, 1.745329252f);
        sample(0, 0); require(FPGA_TurnReadYawRate(&rate));
        ++ticks; require(!FPGA_TurnReadYawRate(&rate));
        sample(131, 1); require(FPGA_TurnReadYawRate(&rate)); close_rate(rate, 0.0f);
        ticks = 0xfffffff0u; sample(131, 1); ticks += 100u;
        require(FPGA_TurnReadYawRate(&rate)); ++ticks;
        require(!FPGA_TurnReadYawRate(&rate));
    } else if (!strcmp(scenario, "nack")) {
        calibrate(200, 0); sample(131, 1); require(FPGA_TurnReadYawRate(&rate));
        assert(argc == 4); nack_at = (unsigned)atoi(argv[3]);
        sample(6681, 1); require(!FPGA_TurnReadYawRate(&rate));
        require(ack_count >= nack_at); require(stops > 0);
        nack_at = 0; sample(131, 1); require(FPGA_TurnReadYawRate(&rate));
    } else if (!strcmp(scenario, "id") || !strcmp(scenario, "range") || !strcmp(scenario, "sleep")) {
        calibrate(200, 0); sample(131, 1); require(FPGA_TurnReadYawRate(&rate));
        if (!strcmp(scenario, "id")) registers[0][model ? REG_ADD_WIA : MPU6050_RA_WHO_AM_I] = 0;
        else if (!strcmp(scenario, "range")) registers[model ? 2 : 0][model ? REG_ADD_GYRO_CONFIG_1 : MPU6050_RA_GYRO_CONFIG] = 0;
        else registers[0][model ? REG_ADD_PWR_MGMT_1 : MPU6050_RA_PWR_MGMT_1] = 0x40;
        sample(6681, 1); require(!FPGA_TurnReadYawRate(&rate)); require(bank == 0);
    } else if (!strcmp(scenario, "variance")) {
        calibrate(200, 1); sample(131, 1); require(!FPGA_TurnReadYawRate(&rate));
    } else if (!strcmp(scenario, "moving_reset")) {
        calibrate(200, 0); SysVal.Time_count = CONTROL_DELAY-1;
        robot.MOTOR_D.Encoder = 0.1f; sample(131, 1); robot.MOTOR_D.Encoder = 0;
        SysVal.Time_count = CONTROL_DELAY; sample(131, 1);
        require(!FPGA_TurnReadYawRate(&rate));
    } else if (!strcmp(scenario, "excess_bias_reset")) {
        calibrate(200, 0); SysVal.Time_count = CONTROL_DELAY-1; sample(2000, 1);
        SysVal.Time_count = CONTROL_DELAY; sample(131, 1);
        require(!FPGA_TurnReadYawRate(&rate));
    } else if (!strcmp(scenario, "startup_moving")) {
        calibrate(200, 0); robot.MOTOR_A.Encoder = 0.1f; sample(131, 1);
        require(!FPGA_TurnReadYawRate(&rate)); robot.MOTOR_A.Encoder = 0;
        sample(131, 1); require(FPGA_TurnReadYawRate(&rate));
    } else if (!strcmp(scenario, "saturation")) {
        calibrate(200, 0); sample(32767, 1); require(!FPGA_TurnReadYawRate(&rate));
        sample(-32768, 1); require(!FPGA_TurnReadYawRate(&rate));
        sample(131, 1); require(FPGA_TurnReadYawRate(&rate));
    } else if (!strcmp(scenario, "unknown")) {
        SysVal.HardWare_Ver = 3; sample(131, 1); require(!FPGA_TurnReadYawRate(&rate));
        require(read_count == 0);
    } else if (!strcmp(scenario, "count_startup_ack")) {
        sample(131, 1); require(!FPGA_TurnReadYawRate(&rate));
        printf("ACK_COUNT=%u\n", ack_count);
    } else if (!strcmp(scenario, "nack_calibration")) {
        unsigned pin = model ? 0x0f : MPU6050_RA_INT_PIN_CFG;
        unsigned enable = model ? 0x11 : MPU6050_RA_INT_ENABLE;
        calibrate(199, 0);
        SysVal.Time_count = CONTROL_DELAY - 1u;
        registers[0][pin] = 0xf0;
        registers[0][enable] = 0xa0;
        assert(argc == 4); nack_at = (unsigned)atoi(argv[3]);
        sample(131, 1); require(!FPGA_TurnReadYawRate(&rate));
        require(ack_count >= nack_at);
        nack_at = 0;
        SysVal.Time_count = CONTROL_DELAY;
        sample(131, 1);
        /* Even failures after 199 good samples must reset the incomplete
         * calibration; one repaired sample must not authorize turning. */
        require(!FPGA_TurnReadYawRate(&rate));
    } else if (!strcmp(scenario, "count_ack")) {
        calibrate(200, 0); sample(131, 1); require(FPGA_TurnReadYawRate(&rate));
        printf("ACK_COUNT=%u\n", ack_count);
    } else assert(!"unknown scenario");
    printf("PASS CHECKED GYRO: sensor=%s scenario=%s nack_injection=%s ack=%u checks=%u\n",
           model ? "ICM20948" : "MPU6050", scenario, argc == 4 ? argv[3] : "none", ack_count, checks);
    return 0;
}
