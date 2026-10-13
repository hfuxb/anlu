#ifndef FEEDBACK_TEST_SYSTEM_H
#define FEEDBACK_TEST_SYSTEM_H
#include <stdint.h>
#include <stddef.h>
#include <math.h>
#include "sys.h"
#include "Public_StdTypes.h"
#include "MPU6050.h"
#include "ICM20948.h"
#define CONTROL_DELAY 1000u
#define M2T(ms) ((uint32_t)(ms))
typedef struct { uint16_t HardWare_Ver; uint32_t Time_count; } FeedbackTestSys;
typedef struct { float Encoder; } FeedbackTestMotor;
typedef struct {
    FeedbackTestMotor MOTOR_A, MOTOR_B, MOTOR_C, MOTOR_D;
} FeedbackTestRobot;
extern FeedbackTestSys SysVal;
extern FeedbackTestRobot robot;
uint32_t getSysTickCnt(void);
void feedback_test_enter_critical(void);
void feedback_test_exit_critical(void);
#define taskENTER_CRITICAL() feedback_test_enter_critical()
#define taskEXIT_CRITICAL() feedback_test_exit_critical()
#endif
