#ifndef FPGA_TURN_FEEDBACK_H
#define FPGA_TURN_FEEDBACK_H

/* Physical yaw rate. All sensor I2C work belongs to the 100 Hz IMU task. */
void FPGA_TurnFeedbackSample(void);

/* Returns 1 only for a calibrated, checked sample at most 100 ms old.
 * Does not perform I2C and is safe to call from the balance task.
 * Positive Z has the same sign as the existing ROS gyro telemetry.
 */
int FPGA_TurnReadYawRate(float *rate_rad_s);

#endif
