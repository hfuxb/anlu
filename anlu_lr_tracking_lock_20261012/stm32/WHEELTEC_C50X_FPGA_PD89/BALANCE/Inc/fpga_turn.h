#ifndef FPGA_TURN_H
#define FPGA_TURN_H

#include <stdint.h>

enum {
    FPGA_TURN_IDLE = 0, FPGA_TURN_ACCEPTED = 1, FPGA_TURN_RUNNING = 2,
    FPGA_TURN_DONE = 3, FPGA_TURN_CANCELLED = 4, FPGA_TURN_FAULT = 5
};
enum {
    FPGA_TURN_FAULT_NONE = 0, FPGA_TURN_FAULT_PARAMS = 1,
    FPGA_TURN_FAULT_TIMEOUT = 2, FPGA_TURN_FAULT_FEEDBACK = 3,
    FPGA_TURN_FAULT_DISABLED = 4, FPGA_TURN_FAULT_WATCHDOG = 5,
    FPGA_TURN_FAULT_BUSY = 6
};

#define FPGA_TURN_TIMEOUT_TICKS 700u
#define FPGA_TURN_KEEPALIVE_TICKS 30u
#define FPGA_TURN_TOLERANCE_CDEG 150
#define FPGA_TURN_SETTLE_TICKS 20u

typedef struct {
    uint8_t seq;
    int16_t angle_cdeg;
    uint16_t max_w_mrad_s;
    int16_t forward_mm_s;
} FpgaTurnCommand;

typedef struct {
    uint8_t seq, state, fault;
    int16_t progress_cdeg, error_cdeg;
} FpgaTurnStatus;

/* Single-owner portable controller: all functions run in the 100 Hz owner. */
typedef struct {
    FpgaTurnCommand command;
    uint8_t have_seq, state, fault, rejection_pending;
    uint16_t elapsed_ticks, keepalive_ticks, settle_ticks, progress_ticks;
    float progress_rad, progress_checkpoint, angular_rad_s, forward_m_s;
    FpgaTurnStatus rejection;
} FpgaTurn;

void FpgaTurn_Init(FpgaTurn *turn);
/* 1 = new accepted action, 2 = matching duplicate, 0 = rejected. */
int FpgaTurn_Submit(FpgaTurn *turn, const FpgaTurnCommand *command);
void FpgaTurn_Cancel(FpgaTurn *turn);
void FpgaTurn_Fail(FpgaTurn *turn, uint8_t fault);
int FpgaTurn_Active(const FpgaTurn *turn);
void FpgaTurn_Step(FpgaTurn *turn, float measured_yaw_rad_s,
                   int feedback_valid, int enabled, int watchdog_lost);
/* A rejection is returned once; the retained action snapshot is unaffected. */
void FpgaTurn_GetStatus(FpgaTurn *turn, FpgaTurnStatus *status);
void FpgaTurn_EncodeStatus(const FpgaTurnStatus *status, uint8_t frame[11]);

#ifndef FPGA_TURN_HOST_TEST
/* USART3 IRQ publishes only validated complete mode-0 / mode-0x10 frames. */
void FPGA_TurnPublishFrameFromISR(const uint8_t frame[11]);
void FPGA_TurnBalanceStep(void);
/* Caller holds a critical section only while copying this 11-byte snapshot. */
void FPGA_TurnStatusFrame(uint8_t frame[11]);
#endif
#endif
