#ifndef FEEDBACK_TEST_PUBLIC_TYPES_H
#define FEEDBACK_TEST_PUBLIC_TYPES_H
#include <stdint.h>
#include <stdbool.h>
/* Exclude MCU-only peripheral structs when the vendor header includes its
 * neighboring Public_StdTypes.h by quoted path. Sensor register definitions
 * still come from the unmodified vendor MPU6050/ICM20948 headers. */
#define _PUBILC_STDTYPES_H_
#endif
