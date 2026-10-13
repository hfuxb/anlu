#include "fpga_turn.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static FpgaTurnCommand command(uint8_t seq, int16_t angle)
{
    FpgaTurnCommand result = {0};
    result.seq = seq; result.angle_cdeg = angle; result.max_w_mrad_s = 700;
    return result;
}
static void refresh_step(FpgaTurn *turn, float rate, int tick)
{
    if(tick % 5 == 0) assert(FpgaTurn_Submit(turn, &turn->command) == 2);
    FpgaTurn_Step(turn, rate, 1, 1, 0);
}
static int run_plant(FpgaTurn *turn, float rate, float *absolute_heading)
{
    int tick;
    for(tick = 0; tick < 700 && FpgaTurn_Active(turn); ++tick) {
        /* A lagging closed wheel loop/chassis; heading crosses +/-180 degrees. */
        rate += (turn->angular_rad_s - rate) * 0.12f;
        *absolute_heading += rate * 0.01f;
        if(*absolute_heading > 3.14159265359f) *absolute_heading -= 6.28318530718f;
        if(*absolute_heading < -3.14159265359f) *absolute_heading += 6.28318530718f;
        refresh_step(turn, rate, tick);
        assert(fabsf(turn->angular_rad_s) <= 0.70001f);
    }
    assert(turn->state == FPGA_TURN_DONE);
    assert(fabsf(turn->command.angle_cdeg - turn->progress_rad * 18000.0f / 3.14159265359f) <= 150.0f);
    assert(turn->angular_rad_s == 0.0f && turn->forward_m_s == 0.0f);
    return tick;
}
static void test_left_right_and_wrap(void)
{
    int sign;
    for(sign = -1; sign <= 1; sign += 2) {
        FpgaTurn turn;
        FpgaTurnCommand request = command(1, (int16_t)(sign * 9000));
        float heading = sign * 179.0f * 3.14159265359f / 180.0f;
        FpgaTurn_Init(&turn);
        assert(FpgaTurn_Submit(&turn, &request) == 1);
        assert(turn.state == FPGA_TURN_ACCEPTED);
        printf("%s 90 degree turn across absolute heading wrap: %d ticks\n",
               sign > 0 ? "left" : "right", run_plant(&turn, 0.0f, &heading));
        assert(sign * turn.progress_rad > 1.5f);
    }
}
static void test_duplicates_busy_terminal_and_sequence(void)
{
    FpgaTurn turn;
    FpgaTurnStatus status;
    FpgaTurnCommand first = command(254, 9000), altered = first, next = command(255, -9000);
    float heading = 0.0f, saved;
    FpgaTurn_Init(&turn);
    assert(FpgaTurn_Submit(&turn, &first) == 1);
    refresh_step(&turn, 0.2f, 1);
    saved = turn.progress_rad;
    assert(FpgaTurn_Submit(&turn, &first) == 2);
    assert(turn.progress_rad == saved && turn.elapsed_ticks == 1);
    altered.angle_cdeg = 8000;
    assert(FpgaTurn_Submit(&turn, &altered) == 0);
    FpgaTurn_GetStatus(&turn, &status);
    assert(status.seq == 254 && status.state == FPGA_TURN_FAULT && status.fault == FPGA_TURN_FAULT_PARAMS);
    assert(turn.state == FPGA_TURN_RUNNING && turn.progress_rad == saved);
    assert(FpgaTurn_Submit(&turn, &next) == 0);
    FpgaTurn_GetStatus(&turn, &status);
    assert(status.seq == 255 && status.fault == FPGA_TURN_FAULT_BUSY);
    assert(turn.command.seq == 254 && turn.state == FPGA_TURN_RUNNING);
    run_plant(&turn, 0.0f, &heading);
    saved = turn.progress_rad;
    assert(FpgaTurn_Submit(&turn, &first) == 2);
    FpgaTurn_Step(&turn, 1.0f, 1, 1, 0);
    FpgaTurn_Cancel(&turn); /* Normal mode-0 must preserve a completed snapshot. */
    assert(turn.state == FPGA_TURN_DONE && turn.progress_rad == saved);
    assert(FpgaTurn_Submit(&turn, &next) == 1);
    FpgaTurn_Cancel(&turn);
    assert(turn.state == FPGA_TURN_CANCELLED);
    assert(FpgaTurn_Submit(&turn, &next) == 2);
    assert(turn.state == FPGA_TURN_CANCELLED);
    next.seq = 0;
    assert(FpgaTurn_Submit(&turn, &next) == 1); /* Modular sequence wrap. */
    FpgaTurn_Cancel(&turn);
    assert(FpgaTurn_Submit(&turn, &first) == 0); /* Delayed old request. */
}
static void test_fail_closed_and_limits(void)
{
    FpgaTurn turn;
    FpgaTurnCommand request = command(1, 9000);
    int tick;
    FpgaTurn_Init(&turn); assert(FpgaTurn_Submit(&turn, &request) == 1);
    FpgaTurn_Step(&turn, 0.0f, 0, 1, 0);
    assert(turn.state == FPGA_TURN_FAULT && turn.fault == FPGA_TURN_FAULT_FEEDBACK);
    assert(FpgaTurn_Submit(&turn, &request) == 2 && turn.state == FPGA_TURN_FAULT);
    FpgaTurn_Init(&turn); assert(FpgaTurn_Submit(&turn, &request) == 1);
    FpgaTurn_Step(&turn, 0.0f, 1, 0, 0);
    assert(turn.fault == FPGA_TURN_FAULT_DISABLED);
    FpgaTurn_Init(&turn); assert(FpgaTurn_Submit(&turn, &request) == 1);
    FpgaTurn_Step(&turn, 0.0f, 1, 1, 1);
    assert(turn.fault == FPGA_TURN_FAULT_WATCHDOG);
    FpgaTurn_Init(&turn); assert(FpgaTurn_Submit(&turn, &request) == 1);
    for(tick = 0; tick < 31; ++tick) FpgaTurn_Step(&turn, 0.0f, 1, 1, 0);
    assert(turn.fault == FPGA_TURN_FAULT_WATCHDOG && turn.elapsed_ticks == 30);
    FpgaTurn_Init(&turn); assert(FpgaTurn_Submit(&turn, &request) == 1);
    for(tick = 0; tick < 120; ++tick) refresh_step(&turn, 0.0f, tick);
    assert(turn.fault == FPGA_TURN_FAULT_FEEDBACK && turn.angular_rad_s == 0.0f);
    FpgaTurn_Init(&turn); assert(FpgaTurn_Submit(&turn, &request) == 1);
    refresh_step(&turn, 0.1f, 0);
    FpgaTurn_Step(&turn, NAN, 1, 1, 0);
    assert(turn.fault == FPGA_TURN_FAULT_FEEDBACK && turn.angular_rad_s == 0.0f);
    FpgaTurn_Init(&turn); request.angle_cdeg = 18000;
    assert(FpgaTurn_Submit(&turn, &request) == 1);
    for(tick = 0; tick <= 700; ++tick) refresh_step(&turn, 0.03f, tick);
    assert(turn.fault == FPGA_TURN_FAULT_TIMEOUT);
    FpgaTurn_Init(&turn); request.angle_cdeg = 0;
    assert(FpgaTurn_Submit(&turn, &request) == 0);
    request.angle_cdeg = 9000; request.max_w_mrad_s = 0;
    assert(FpgaTurn_Submit(&turn, &request) == 0);
    request.max_w_mrad_s = 700; request.forward_mm_s = 301;
    assert(FpgaTurn_Submit(&turn, &request) == 0);
}
static void test_overshoot_and_status(void)
{
    FpgaTurn turn;
    FpgaTurnCommand request = command(7, 9000);
    FpgaTurnStatus status = {7, FPGA_TURN_RUNNING, 0, -12345, 2345};
    uint8_t frame[11], checksum = 0;
    float heading = 0.0f;
    int i;
    FpgaTurn_Init(&turn); assert(FpgaTurn_Submit(&turn, &request) == 1);
    turn.progress_rad = 100.0f * 3.14159265359f / 180.0f;
    FpgaTurn_Step(&turn, 0.35f, 1, 1, 0);
    assert(turn.angular_rad_s < 0.0f);
    printf("overshoot reversal and convergence: %d ticks\n", run_plant(&turn, 0.35f, &heading));
    FpgaTurn_EncodeStatus(&status, frame);
    assert(frame[0] == 0x7c && frame[1] == 0xa1 && frame[2] == 7 && frame[10] == 0x7e);
    assert((int16_t)((uint16_t)frame[4] << 8 | frame[5]) == -12345);
    assert((int16_t)((uint16_t)frame[6] << 8 | frame[7]) == 2345);
    for(i = 0; i < 9; ++i) checksum ^= frame[i];
    assert(frame[9] == checksum);
}
int main(void)
{
    test_left_right_and_wrap();
    test_duplicates_busy_terminal_and_sequence();
    test_fail_closed_and_limits();
    test_overshoot_and_status();
    puts("PASS: turn controller, idempotence, sequencing, fault stops, status packet");
    return 0;
}
