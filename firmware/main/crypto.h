#pragma once

#include "common.h"

// BLE Connection Security (ECDH) & Group Ratchet variables
extern uint8_t ble_session_key[16];
extern bool ble_session_established;
extern uint8_t server_pub_key[65]; // 0x04 + 64 bytes P-256 public key

extern uint8_t current_group_key[16];
extern uint8_t group_key_epoch;

#define MAX_EPOCH_KEYS 16
extern uint8_t epoch_key_ring[MAX_EPOCH_KEYS][16];
extern int epoch_key_ring_start;
extern int epoch_key_ring_len;

// Function declarations
void crypto_init(void);
int crypto_calc_session_key(const uint8_t client_pub[65]);
void ratchet_group_key(void);
const uint8_t *get_group_key_for_epoch(uint8_t epoch);
void save_epoch_key(void);

int aes_gcm_encrypt(const uint8_t *plaintext, size_t len,
                    const uint8_t *key,
                    uint8_t *out_nonce, uint8_t *out_ciphertext,
                    uint8_t *out_tag);

int aes_gcm_decrypt(const uint8_t *ciphertext, size_t len,
                    const uint8_t *key,
                    const uint8_t *nonce, const uint8_t *tag,
                    uint8_t *out_plaintext);
