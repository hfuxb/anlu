#include "fpga_turn.h"
#include <string.h>

#define TURN_PI 3.14159265358979323846f
#define CDEG_TO_RAD (TURN_PI / 18000.0f)
#define RAD_TO_CDEG (18000.0f / TURN_PI)
#define TURN_DT 0.01f

static float turn_abs(float value) { return value < 0.0f ? -value : value; }
static float turn_limit(float value, float limit)
{
    if(value > limit) return limit;
    if(value < -limit) return -limit;
    return value;
}
static int16_t turn_cdeg(float radians)
{
    float value = radians * RAD_TO_CDEG;
    if(value > 32767.0f) value = 32767.0f;
    if(value < -32768.0f) value = -32768.0f;
    return (int16_t)(value + (value >= 0.0f ? 0.5f : -0.5f));
}
static void turn_reject(FpgaTurn *turn, const FpgaTurnCommand *command, uint8_t fault)
{
    turn->rejection.seq = command->seq;
    turn->rejection.state = FPGA_TURN_FAULT;
    turn->rejection.fault = fault;
    turn->rejection.progress_cdeg = 0;
    turn->rejection.error_cdeg = command->angle_cdeg;
    turn->rejection_pending = 1;
}
void FpgaTurn_Init(FpgaTurn *turn) { memset(turn, 0, sizeof(*turn)); }
int FpgaTurn_Active(const FpgaTurn *turn)
{
    return turn->state == FPGA_TURN_ACCEPTED || turn->state == FPGA_TURN_RUNNING;
}
int FpgaTurn_Submit(FpgaTurn *turn, const FpgaTurnCommand *command)
{
    uint8_t delta;
    if(turn->have_seq && command->seq == turn->command.seq) {
        if(command->angle_cdeg != turn->command.angle_cdeg ||
           command->max_w_mrad_s != turn->command.max_w_mrad_s ||
           command->forward_mm_s != turn->command.forward_mm_s) {
            turn_reject(turn, command, FPGA_TURN_FAULT_PARAMS);
            return 0;
        }
        /* Terminal states are retained: keepalive never restarts an action. */
        turn->keepalive_ticks = 0;
        return 2;
    }
    if(FpgaTurn_Active(turn)) {
        turn_reject(turn, command, FPGA_TURN_FAULT_BUSY);
        return 0;
    }
    delta = (uint8_t)(command->seq - turn->command.seq);
    if((turn->have_seq && (delta == 0u || delta >= 128u)) ||
       command->angle_cdeg < -18000 || command->angle_cdeg > 18000 ||
       (command->angle_cdeg > -100 && command->angle_cdeg < 100) ||
       command->max_w_mrad_s < 100u || command->max_w_mrad_s > 1000u ||
       command->forward_mm_s < -300 || command->forward_mm_s > 300) {
        turn_reject(turn, command, FPGA_TURN_FAULT_PARAMS);
        return 0;
    }
    turn->command = *command;
    turn->have_seq = 1;
    turn->state = FPGA_TURN_ACCEPTED;
    turn->fault = FPGA_TURN_FAULT_NONE;
    turn->elapsed_ticks = turn->keepalive_ticks = turn->settle_ticks = 0;
    turn->progress_ticks = 0;
    turn->progress_rad = turn->progress_checkpoint = 0.0f;
    turn->angular_rad_s = turn->forward_m_s = 0.0f;
    return 1;
}
void FpgaTurn_Cancel(FpgaTurn *turn)
{
    if(FpgaTurn_Active(turn)) {
        turn->state = FPGA_TURN_CANCELLED;
        turn->fault = FPGA_TURN_FAULT_NONE;
        turn->angular_rad_s = turn->forward_m_s = 0.0f;
    }
}
void FpgaTurn_Fail(FpgaTurn *turn, uint8_t fault)
{
    if(FpgaTurn_Active(turn)) {
        turn->state = FPGA_TURN_FAULT;
        turn->fault = fault;
        turn->angular_rad_s = turn->forward_m_s = 0.0f;
    }
}
void FpgaTurn_Step(FpgaTurn *turn, float measured_yaw_rad_s,
                   int feedback_valid, int enabled, int watchdog_lost)
{
    float error, requested, max_w, step;
    if(!FpgaTurn_Active(turn)) return;
    if(!enabled) { FpgaTurn_Fail(turn, FPGA_TURN_FAULT_DISABLED); return; }
    if(watchdog_lost || ++turn->keepalive_ticks > FPGA_TURN_KEEPALIVE_TICKS) {
        FpgaTurn_Fail(turn, FPGA_TURN_FAULT_WATCHDOG); return;
    }
    if(!feedback_valid || measured_yaw_rad_s != measured_yaw_rad_s ||
       turn_abs(measured_yaw_rad_s) > 8.73f) {
        FpgaTurn_Fail(turn, FPGA_TURN_FAULT_FEEDBACK); return;
    }
    if(++turn->elapsed_ticks > FPGA_TURN_TIMEOUT_TICKS) {
        FpgaTurn_Fail(turn, FPGA_TURN_FAULT_TIMEOUT); return;
    }
    turn->state = FPGA_TURN_RUNNING;
    /* Relative integration cannot wrap at an absolute heading of +/-180 deg. */
    turn->progress_rad += measured_yaw_rad_s * TURN_DT;
    error = turn->command.angle_cdeg * CDEG_TO_RAD - turn->progress_rad;
    if(turn_abs(error) <= FPGA_TURN_TOLERANCE_CDEG * CDEG_TO_RAD &&
       turn_abs(measured_yaw_rad_s) < 0.06f) {
        if(++turn->settle_ticks >= FPGA_TURN_SETTLE_TICKS) {
            turn->state = FPGA_TURN_DONE;
            turn->angular_rad_s = turn->forward_m_s = 0.0f;
            return;
        }
    } else turn->settle_ticks = 0;

    /* Detect a stuck chassis/sensor without mistaking final settling for a stall. */
    if(++turn->progress_ticks >= 120u) {
        if(turn_abs(error) > 300.0f * CDEG_TO_RAD &&
           turn_abs(turn->progress_rad - turn->progress_checkpoint) < 50.0f * CDEG_TO_RAD) {
            FpgaTurn_Fail(turn, FPGA_TURN_FAULT_FEEDBACK); return;
        }
        turn->progress_ticks = 0;
        turn->progress_checkpoint = turn->progress_rad;
    }
    max_w = turn->command.max_w_mrad_s * 0.001f;
    requested = turn_limit(1.8f * error - 0.25f * measured_yaw_rad_s, max_w);
    if(turn_abs(error) <= FPGA_TURN_TOLERANCE_CDEG * CDEG_TO_RAD) requested = 0.0f;
    /* Outside tolerance a small floor overcomes static wheel friction. */
    else if(turn_abs(requested) < 0.10f)
        requested = error > 0.0f ? 0.10f : -0.10f;
    step = turn_limit(requested - turn->angular_rad_s, 1.4f * TURN_DT);
    turn->angular_rad_s = turn_limit(turn->angular_rad_s + step, max_w);
    turn->forward_m_s = turn->command.forward_mm_s * 0.001f;
}
void FpgaTurn_GetStatus(FpgaTurn *turn, FpgaTurnStatus *status)
{
    if(turn->rejection_pending) {
        *status = turn->rejection;
        turn->rejection_pending = 0;
    } else {
        status->seq = turn->command.seq;
        status->state = turn->state;
        status->fault = turn->fault;
        status->progress_cdeg = turn_cdeg(turn->progress_rad);
        status->error_cdeg = turn->have_seq ?
            turn_cdeg(turn->command.angle_cdeg * CDEG_TO_RAD - turn->progress_rad) : 0;
    }
}
void FpgaTurn_EncodeStatus(const FpgaTurnStatus *status, uint8_t frame[11])
{
    uint8_t i, checksum = 0;
    frame[0] = 0x7c; frame[1] = 0xa1; frame[2] = status->seq;
    frame[3] = status->state;
    frame[4] = (uint8_t)((uint16_t)status->progress_cdeg >> 8);
    frame[5] = (uint8_t)status->progress_cdeg;
    frame[6] = (uint8_t)((uint16_t)status->error_cdeg >> 8);
    frame[7] = (uint8_t)status->error_cdeg; frame[8] = status->fault;
    for(i = 0; i < 9u; ++i) checksum ^= frame[i];
    frame[9] = checksum; frame[10] = 0x7e;
}

#ifndef FPGA_TURN_HOST_TEST
#include "balance_task.h"
#include "fpga_turn_feedback.h"

#define TURN_MAILBOX_SIZE 8u
static FpgaTurn fpga_turn;
static volatile uint8_t turn_mailbox[TURN_MAILBOX_SIZE][11];
static volatile uint8_t turn_write, turn_read, turn_overflow;
/* Data and balance tasks can have the same priority. Publish bytes only after
 * the complete owner update; the telemetry task never reads live float/state.
 * Retain a rejection separately until the 20 Hz sender has copied it.
 */
static volatile uint8_t turn_status_frame[11] =
    {0x7c, 0xa1, 0, 0, 0, 0, 0, 0, 0, 0xdd, 0x7e};
static volatile uint8_t turn_rejection_frame[11], turn_rejection_ready;

static void turn_publish_status(void)
{
    FpgaTurnStatus status;
    uint8_t normal[11], rejection[11], rejected, i;
    rejected = fpga_turn.rejection_pending;
    if(rejected) {
        FpgaTurn_GetStatus(&fpga_turn, &status);
        FpgaTurn_EncodeStatus(&status, rejection);
    }
    FpgaTurn_GetStatus(&fpga_turn, &status);
    FpgaTurn_EncodeStatus(&status, normal);
    taskENTER_CRITICAL();
    for(i = 0; i < 11u; ++i) {
        turn_status_frame[i] = normal[i];
        if(rejected) turn_rejection_frame[i] = rejection[i];
    }
    if(rejected) turn_rejection_ready = 1u;
    taskEXIT_CRITICAL();
}

static int16_t turn_s16(const uint8_t *bytes)
{
    return (int16_t)(((uint16_t)bytes[0] << 8) | bytes[1]);
}
void FPGA_TurnPublishFrameFromISR(const uint8_t frame[11])
{
    uint8_t i, next = (uint8_t)((turn_write + 1u) % TURN_MAILBOX_SIZE);
    if(next == turn_read) { turn_overflow = 1; return; }
    for(i = 0; i < 11u; ++i) turn_mailbox[turn_write][i] = frame[i];
    __DMB();
    turn_write = next;
}
static void turn_zero_speed(void)
{
    robot_control.Vx = robot_control.Vy = robot_control.Vz = 0.0f;
    robot_control.smooth_Vx = robot_control.smooth_Vy = robot_control.smooth_Vz = 0.0f;
}
void FPGA_TurnBalanceStep(void)
{
    uint8_t frame[11], i, overflow, was_active;
    uint32_t irq_mask;
    FpgaTurnCommand command;
    float yaw_rate = 0.0f;
    int valid, enabled, result;
    was_active = (uint8_t)FpgaTurn_Active(&fpga_turn);
    irq_mask = __get_PRIMASK(); __disable_irq();
    overflow = turn_overflow; turn_overflow = 0;
    if(!irq_mask) __enable_irq();
    while(turn_read != turn_write) {
        irq_mask = __get_PRIMASK(); __disable_irq();
        for(i = 0; i < 11u; ++i) frame[i] = turn_mailbox[turn_read][i];
        turn_read = (uint8_t)((turn_read + 1u) % TURN_MAILBOX_SIZE);
        if(!irq_mask) __enable_irq();
        if(frame[1] == 0u) {
            FpgaTurn_Cancel(&fpga_turn);
            Set_Control_Mode(_ROS_Control);
            charger.AllowRecharge = 0;
            robot_control.command_lostcount = 0;
            robot_control.Vx = turn_s16(&frame[3]) * 0.001f;
            robot_control.Vy = turn_s16(&frame[5]) * 0.001f;
            robot_control.Vz = turn_s16(&frame[7]) * 0.001f;
#if defined AKM_CAR
            robot_control.Vz = Akm_Vz_to_Angle(robot_control.Vx, robot_control.Vz);
#endif
            if(robot_control.Vx == 0.0f && robot_control.Vy == 0.0f && robot_control.Vz == 0.0f)
                turn_zero_speed();
            /* A normal command owns the velocities after cancellation. */
            was_active = 0;
        } else if(frame[1] == 0x10u) {
            command.seq = frame[2]; command.angle_cdeg = turn_s16(&frame[3]);
            command.max_w_mrad_s = (uint16_t)turn_s16(&frame[5]);
            command.forward_mm_s = turn_s16(&frame[7]);
            result = FpgaTurn_Submit(&fpga_turn, &command);
            if(result != 0) robot_control.command_lostcount = 0;
            if(result == 1) {
                Set_Control_Mode(_ROS_Control);
                charger.AllowRecharge = 0;
                turn_zero_speed();
                was_active = 1;
            }
        }
    }
    valid = FPGA_TurnReadYawRate(&yaw_rate);
    enabled = 0;
#if defined _4WD_CAR
    enabled = SysVal.Time_count > CONTROL_DELAY + 230 &&
        Get_Control_Mode(_ROS_Control) && charger.AllowRecharge == 0 &&
        robot_control.FlagStop == 0 && robot.voltage >= 20.0f && EN != 0 &&
        robot_control.SoftWare_Stop == 0 && robot_check.errorflag == 0 &&
        robot_check.DeepCheck == 0;
#endif
    FpgaTurn_Step(&fpga_turn, yaw_rate, valid, enabled,
        overflow || (SysVal.SecurityLevel == 0 && robot_control.command_lostcount > BALANCE_TASK_RATE));
    if(FpgaTurn_Active(&fpga_turn)) {
        robot_control.Vx = fpga_turn.forward_m_s;
        robot_control.Vy = 0.0f;
        robot_control.Vz = fpga_turn.angular_rad_s;
    } else if(was_active || overflow) turn_zero_speed();
    turn_publish_status();
}
void FPGA_TurnStatusFrame(uint8_t frame[11])
{
    uint8_t i;
    /* Caller holds the short critical section around this byte copy. */
    for(i = 0; i < 11u; ++i)
        frame[i] = turn_rejection_ready ? turn_rejection_frame[i] : turn_status_frame[i];
    turn_rejection_ready = 0u;
}
#endif
