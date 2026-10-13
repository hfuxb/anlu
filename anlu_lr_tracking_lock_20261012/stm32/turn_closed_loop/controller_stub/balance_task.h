#ifndef TEST_BALANCE_TASK_H
#define TEST_BALANCE_TASK_H
#include <stdint.h>
#define _4WD_CAR 1
#define _ROS_Control 3
#define CONTROL_DELAY 1000
#define BALANCE_TASK_RATE 100
extern int EN;
extern struct TestControl { float Vx,Vy,Vz,smooth_Vx,smooth_Vy,smooth_Vz;
    unsigned command_lostcount,FlagStop,SoftWare_Stop; } robot_control;
extern struct TestSystem { unsigned Time_count,SecurityLevel; } SysVal;
extern struct TestRobot { float voltage; } robot;
extern struct TestCheck { unsigned errorflag,DeepCheck; } robot_check;
extern struct TestCharger { unsigned AllowRecharge; } charger;
void Set_Control_Mode(int mode);
int Get_Control_Mode(int mode);
void test_enter_critical(void);
void test_exit_critical(void);
#define taskENTER_CRITICAL() test_enter_critical()
#define taskEXIT_CRITICAL() test_exit_critical()
static inline uint32_t __get_PRIMASK(void) { return 0; }
static inline void __disable_irq(void) { }
static inline void __enable_irq(void) { }
static inline void __DMB(void) { }
#endif
