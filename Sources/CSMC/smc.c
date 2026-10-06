#include "smc.h"

#include <IOKit/IOKitLib.h>
#include <string.h>

#define KERNEL_INDEX_SMC      2
#define SMC_CMD_READ_BYTES    5
#define SMC_CMD_WRITE_BYTES   6
#define SMC_CMD_READ_INDEX    8
#define SMC_CMD_READ_KEYINFO  9

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    uint16_t release;
} SMCKeyData_vers_t;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    char dataAttributes;
} SMCKeyData_keyInfo_t;

typedef struct {
    uint32_t key;
    SMCKeyData_vers_t vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t keyInfo;
    char result;
    char status;
    char data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData_t;

static io_connect_t g_conn = 0;

int smc_open(void) {
    if (g_conn) return 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return -1;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &g_conn);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS) { g_conn = 0; return (int)kr; }
    return 0;
}

void smc_close(void) {
    if (g_conn) { IOServiceClose(g_conn); g_conn = 0; }
}

static kern_return_t smc_call(SMCKeyData_t *in, SMCKeyData_t *out) {
    if (!g_conn && smc_open() != 0) return kIOReturnNotOpen;
    size_t outSize = sizeof(SMCKeyData_t);
    return IOConnectCallStructMethod(g_conn, KERNEL_INDEX_SMC, in, sizeof(SMCKeyData_t), out, &outSize);
}

static int smc_key_info(uint32_t key, SMCKeyData_keyInfo_t *info) {
    SMCKeyData_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key;
    in.data8 = SMC_CMD_READ_KEYINFO;
    kern_return_t kr = smc_call(&in, &out);
    if (kr != KERN_SUCCESS) return (int)kr;
    if (out.result != 0) return out.result;
    *info = out.keyInfo;
    return 0;
}

int smc_read(uint32_t key, smc_value_t *value) {
    SMCKeyData_keyInfo_t info;
    int rc = smc_key_info(key, &info);
    if (rc != 0) return rc;

    SMCKeyData_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key;
    in.keyInfo.dataSize = info.dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    kern_return_t kr = smc_call(&in, &out);
    if (kr != KERN_SUCCESS) return (int)kr;
    if (out.result != 0) return out.result;

    memset(value, 0, sizeof(*value));
    value->key = key;
    value->dataType = info.dataType;
    value->dataSize = info.dataSize > 32 ? 32 : info.dataSize;
    memcpy(value->bytes, out.bytes, value->dataSize);
    return 0;
}

int smc_write(uint32_t key, const uint8_t *bytes, uint32_t size) {
    SMCKeyData_keyInfo_t info;
    int rc = smc_key_info(key, &info);
    if (rc != 0) return rc;
    if (info.dataSize != size || size > 32) return -2;

    SMCKeyData_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = key;
    in.data8 = SMC_CMD_WRITE_BYTES;
    in.keyInfo.dataSize = size;
    memcpy(in.bytes, bytes, size);
    kern_return_t kr = smc_call(&in, &out);
    if (kr != KERN_SUCCESS) return (int)kr;
    return out.result;
}

uint32_t smc_key_count(void) {
    smc_value_t v;
    if (smc_read('#KEY', &v) != 0) return 0;
    return ((uint32_t)v.bytes[0] << 24) | ((uint32_t)v.bytes[1] << 16) | ((uint32_t)v.bytes[2] << 8) | v.bytes[3];
}

uint32_t smc_key_at_index(uint32_t index) {
    SMCKeyData_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.data8 = SMC_CMD_READ_INDEX;
    in.data32 = index;
    if (smc_call(&in, &out) != KERN_SUCCESS || out.result != 0) return 0;
    return out.key;
}
