#include "csmc.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_READ_INDEX 8
#define SMC_CMD_READ_KEYINFO 9

typedef struct { char major, minor, build, reserved; uint16_t release; } SMCVers;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } SMCPLimit;
typedef struct { uint32_t dataSize, dataType; uint8_t dataAttributes; } SMCKeyInfo;
typedef struct {
    uint32_t key;
    SMCVers vers;
    SMCPLimit pLimitData;
    SMCKeyInfo keyInfo;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData;

static uint32_t fourcc(const char k[4]) {
    return ((uint32_t)(uint8_t)k[0] << 24) | ((uint32_t)(uint8_t)k[1] << 16) | ((uint32_t)(uint8_t)k[2] << 8) | (uint8_t)k[3];
}
static void unfourcc(uint32_t v, char out[5]) {
    out[0] = (char)(v >> 24); out[1] = (char)(v >> 16); out[2] = (char)(v >> 8); out[3] = (char)v; out[4] = 0;
}

uint32_t csmc_open(void) {
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return 0;
    io_connect_t conn = 0;
    kern_return_t r = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    IOObjectRelease(svc);
    return r == KERN_SUCCESS ? conn : 0;
}

void csmc_close(uint32_t conn) { if (conn) IOServiceClose(conn); }

static kern_return_t call(uint32_t conn, SMCKeyData *in, SMCKeyData *out) {
    size_t outSize = sizeof(SMCKeyData);
    return IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, in, sizeof(SMCKeyData), out, &outSize);
}

int32_t csmc_key_count(uint32_t conn) {
    uint8_t bytes[32]; char type[5];
    int32_t n = csmc_read_key(conn, "#KEY", type, bytes);
    if (n < 4) return -1;
    return (int32_t)(((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) | bytes[3]);
}

bool csmc_key_at_index(uint32_t conn, uint32_t index, char out[5]) {
    SMCKeyData in, res; memset(&in, 0, sizeof in); memset(&res, 0, sizeof res);
    in.data8 = SMC_CMD_READ_INDEX; in.data32 = index;
    if (call(conn, &in, &res) != KERN_SUCCESS || res.result != 0) return false;
    unfourcc(res.key, out);
    return true;
}

int32_t csmc_read_key(uint32_t conn, const char key[4], char type_out[5], uint8_t bytes_out[32]) {
    SMCKeyData in, res; memset(&in, 0, sizeof in); memset(&res, 0, sizeof res);
    in.key = fourcc(key); in.data8 = SMC_CMD_READ_KEYINFO;
    if (call(conn, &in, &res) != KERN_SUCCESS || res.result != 0) return -1;
    uint32_t size = res.keyInfo.dataSize;
    unfourcc(res.keyInfo.dataType, type_out);
    if (size == 0 || size > 32) return -1;
    SMCKeyData in2, res2; memset(&in2, 0, sizeof in2); memset(&res2, 0, sizeof res2);
    in2.key = in.key; in2.keyInfo.dataSize = size; in2.data8 = SMC_CMD_READ_BYTES;
    if (call(conn, &in2, &res2) != KERN_SUCCESS || res2.result != 0) return -1;
    memcpy(bytes_out, res2.bytes, size);
    return (int32_t)size;
}
