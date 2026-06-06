#include "crypto.h"
#include "esp_random.h"

// mbedTLS Cryptography & ECDH
#include "mbedtls/gcm.h"
#include "mbedtls/sha256.h"
#include "mbedtls/ecdh.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"

// Global definition of AES key
const uint8_t AES_KEY[16] = {
    0x4D, 0x65, 0x73, 0x68, 0x4F, 0x53, 0x4B, 0x65,
    0x79, 0x31, 0x32, 0x33, 0x21, 0x40, 0x23, 0x24}; // "MeshOSKey123!@#$"

// Definitions of crypt/sec variables
uint8_t ble_session_key[16] = {0};
bool ble_session_established = false;
uint8_t server_pub_key[65] __attribute__((aligned(4))) = {0};

static mbedtls_ecp_group server_grp;
static mbedtls_mpi server_d;
static mbedtls_ecp_point server_Q;

void crypto_init(void) {
  mbedtls_ecp_group_init(&server_grp);
  mbedtls_mpi_init(&server_d);
  mbedtls_ecp_point_init(&server_Q);

  mbedtls_entropy_context entropy;
  mbedtls_ctr_drbg_context ctr_drbg;
  mbedtls_entropy_init(&entropy);
  mbedtls_ctr_drbg_init(&ctr_drbg);
  const char *pers = "mesh_ecdh_init_v3";
  
  int ret = mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy, (const uint8_t *)pers, strlen(pers));
  if (ret != 0) {
    ESP_LOGE("Crypto", "mbedtls_ctr_drbg_seed failed: -0x%04X", -ret);
    return;
  }

  ret = mbedtls_ecp_group_load(&server_grp, MBEDTLS_ECP_DP_SECP256R1);
  if (ret != 0) {
    ESP_LOGE("Crypto", "mbedtls_ecp_group_load failed: -0x%04X", -ret);
    return;
  }

  ret = mbedtls_ecp_gen_keypair(&server_grp, &server_d, &server_Q, mbedtls_ctr_drbg_random, &ctr_drbg);
  if (ret != 0) {
    ESP_LOGE("Crypto", "mbedtls_ecp_gen_keypair failed: -0x%04X", -ret);
    return;
  }

  size_t olen = 0;
  ret = mbedtls_ecp_point_write_binary(&server_grp, &server_Q, MBEDTLS_ECP_PF_UNCOMPRESSED, &olen, server_pub_key, 65);
  if (ret != 0) {
    ESP_LOGE("Crypto", "mbedtls_ecp_point_write_binary failed: -0x%04X", -ret);
  } else {
    ESP_LOGI("Crypto", "Server ECDH public key generated (len=%u).", (unsigned)olen);
  }

  mbedtls_ctr_drbg_free(&ctr_drbg);
  mbedtls_entropy_free(&entropy);
}

int crypto_calc_session_key(const uint8_t client_pub[65]) {
  mbedtls_entropy_context entropy;
  mbedtls_ctr_drbg_context ctr_drbg;
  mbedtls_ecp_point P;
  mbedtls_mpi z;

  mbedtls_entropy_init(&entropy);
  mbedtls_ctr_drbg_init(&ctr_drbg);
  mbedtls_ecp_point_init(&P);
  mbedtls_mpi_init(&z);

  const char *pers = "mesh_ecdh_calc_v3";
  
  int ret = mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy, (const uint8_t *)pers, strlen(pers));
  if (ret != 0) goto cleanup;

  ret = mbedtls_ecp_point_read_binary(&server_grp, &P, client_pub, 65);
  if (ret != 0) {
    ESP_LOGE("Crypto", "mbedtls_ecp_point_read_binary failed: -0x%04X", -ret);
    goto cleanup;
  }

  ret = mbedtls_ecdh_compute_shared(&server_grp, &z, &P, &server_d, mbedtls_ctr_drbg_random, &ctr_drbg);
  if (ret != 0) {
    ESP_LOGE("Crypto", "mbedtls_ecdh_compute_shared failed: -0x%04X", -ret);
    goto cleanup;
  }

  uint8_t secret[32];
  ret = mbedtls_mpi_write_binary(&z, secret, 32);
  if (ret != 0) goto cleanup;

  mbedtls_sha256_context sha;
  mbedtls_sha256_init(&sha);
  mbedtls_sha256_starts(&sha, 0);
  mbedtls_sha256_update(&sha, secret, 32);
  uint8_t hash[32];
  mbedtls_sha256_finish(&sha, hash);
  mbedtls_sha256_free(&sha);

  memcpy(ble_session_key, hash, 16);
  ble_session_established = true;

cleanup:
  mbedtls_ctr_drbg_free(&ctr_drbg);
  mbedtls_entropy_free(&entropy);
  mbedtls_ecp_point_free(&P);
  mbedtls_mpi_free(&z);
  return ret;
}

uint8_t current_group_key[16] = {
    0x4D, 0x65, 0x73, 0x68, 0x4F, 0x53, 0x4B, 0x65,
    0x79, 0x31, 0x32, 0x33, 0x21, 0x40, 0x23, 0x24};
uint8_t group_key_epoch = 0;

uint8_t epoch_key_ring[MAX_EPOCH_KEYS][16] = {{0}};
int epoch_key_ring_start = 0;
int epoch_key_ring_len = 0;

void save_epoch_key(void) {
  int idx = (epoch_key_ring_start + epoch_key_ring_len) % MAX_EPOCH_KEYS;
  memcpy(epoch_key_ring[idx], current_group_key, 16);
  if (epoch_key_ring_len < MAX_EPOCH_KEYS)
    epoch_key_ring_len++;
  else
    epoch_key_ring_start = (epoch_key_ring_start + 1) % MAX_EPOCH_KEYS;
}

void ratchet_group_key(void) {
  // Save the current epoch's key before overwriting it
  save_epoch_key();

  mbedtls_sha256_context sha_ctx;
  mbedtls_sha256_init(&sha_ctx);
  mbedtls_sha256_starts(&sha_ctx, 0);
  mbedtls_sha256_update(&sha_ctx, current_group_key, 16);
  uint8_t hash[32];
  mbedtls_sha256_finish(&sha_ctx, hash);
  mbedtls_sha256_free(&sha_ctx);
  memcpy(current_group_key, hash, 16);
  group_key_epoch++;
  ESP_LOGI("Crypto", "Group key ratcheted to epoch %u", (unsigned)group_key_epoch);
}

const uint8_t *get_group_key_for_epoch(uint8_t epoch) {
  if (epoch == group_key_epoch) {
    return current_group_key;
  }

  // Use signed comparison to handle uint8_t wrapping correctly
  int8_t diff = (int8_t)((int)group_key_epoch - (int)epoch);
  if (diff > 0) {
    // Past epoch: look up in the ring buffer.
    int oldest_saved = (int)group_key_epoch - epoch_key_ring_len;
    if (oldest_saved < 0) oldest_saved = 0; // Handle early epochs before wrapping
    if (epoch >= (uint8_t)oldest_saved) {
      int dist_from_oldest = (int)epoch - oldest_saved;
      if (dist_from_oldest < epoch_key_ring_len) {
        int idx = (epoch_key_ring_start + dist_from_oldest) % MAX_EPOCH_KEYS;
        return epoch_key_ring[idx];
      }
    }
    ESP_LOGW("Crypto", "Group key epoch %u not in history (oldest saved: %u)",
             epoch, (unsigned)oldest_saved);
    return NULL;
  }

  // Future epoch (diff < 0): ratchet forward, saving each intermediate key.
  while (group_key_epoch != epoch) {
    save_epoch_key();

    mbedtls_sha256_context sha_ctx;
    mbedtls_sha256_init(&sha_ctx);
    mbedtls_sha256_starts(&sha_ctx, 0);
    mbedtls_sha256_update(&sha_ctx, current_group_key, 16);
    uint8_t hash[32];
    mbedtls_sha256_finish(&sha_ctx, hash);
    mbedtls_sha256_free(&sha_ctx);
    memcpy(current_group_key, hash, 16);
    group_key_epoch++;
    ESP_LOGI("Crypto", "Group key advanced to epoch %u", (unsigned)group_key_epoch);
  }
  return current_group_key;
}

int aes_gcm_encrypt(const uint8_t *plaintext, size_t len,
                    const uint8_t *key,
                    uint8_t *out_nonce, uint8_t *out_ciphertext,
                    uint8_t *out_tag) {
  esp_fill_random(out_nonce, AES_GCM_NONCE_LEN);
  mbedtls_gcm_context ctx;
  mbedtls_gcm_init(&ctx);
  int ret = mbedtls_gcm_setkey(&ctx, MBEDTLS_CIPHER_ID_AES, key, 128);
  if (ret == 0) {
    ret = mbedtls_gcm_crypt_and_tag(&ctx, MBEDTLS_GCM_ENCRYPT, len, out_nonce,
                                    AES_GCM_NONCE_LEN, NULL, 0, plaintext,
                                    out_ciphertext, AES_GCM_TAG_LEN, out_tag);
  }
  mbedtls_gcm_free(&ctx);
  return ret;
}

int aes_gcm_decrypt(const uint8_t *ciphertext, size_t len,
                    const uint8_t *key,
                    const uint8_t *nonce, const uint8_t *tag,
                    uint8_t *out_plaintext) {
  mbedtls_gcm_context ctx;
  mbedtls_gcm_init(&ctx);
  int ret = mbedtls_gcm_setkey(&ctx, MBEDTLS_CIPHER_ID_AES, key, 128);
  if (ret == 0) {
    ret = mbedtls_gcm_auth_decrypt(&ctx, len, nonce, AES_GCM_NONCE_LEN, NULL, 0,
                                   tag, AES_GCM_TAG_LEN, ciphertext,
                                   out_plaintext);
  }
  mbedtls_gcm_free(&ctx);
  return ret;
}
