#ifndef CSMC_H
#define CSMC_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t key;        // four-char code
    uint32_t dataType;   // four-char code, e.g. 'sp78', 'flt ', 'fpe2'
    uint32_t dataSize;
    uint8_t  bytes[32];
} smc_value_t;

/// Opens a connection to AppleSMC. Returns 0 on success.
int smc_open(void);
void smc_close(void);

/// Reads a key. Returns 0 on success.
int smc_read(uint32_t key, smc_value_t *out);

/// Writes raw bytes to a key (requires root). Size must match the key's size. Returns 0 on success.
int smc_write(uint32_t key, const uint8_t *bytes, uint32_t size);

/// Total number of keys exposed by the SMC.
uint32_t smc_key_count(void);

/// Key at the given index. Returns 0 on failure.
uint32_t smc_key_at_index(uint32_t index);

#ifdef __cplusplus
}
#endif

#endif
