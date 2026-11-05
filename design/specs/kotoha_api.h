#ifndef KOTOHA_API_H
#define KOTOHA_API_H
/* Engine contract declarations. Implementations are supplied by the runtime.
 * Control messages use UTF-8 and registered capabilities.
 * Input data is borrowed during a call; asynchronous work owns an internal copy.
 * Cancellation is cooperative. Destruction follows terminal-state acknowledgement.
 */
#include <stddef.h>
#include <stdint.h>
#if defined(_WIN32)
# if defined(KOTOHA_BUILD)
#  define KOTOHA_API __declspec(dllexport)
# else
#  define KOTOHA_API __declspec(dllimport)
# endif
#else
# define KOTOHA_API __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif

typedef struct kotoha_runtime kotoha_runtime;
typedef struct kotoha_engine kotoha_engine;
typedef struct kotoha_job kotoha_job;
typedef int32_t kotoha_status;
enum {
 KOTOHA_OK = 0,
 KOTOHA_TIMEOUT = 1,
 KOTOHA_BUFFER_TOO_SMALL = 2,
 KOTOHA_INVALID_ARGUMENT = -1,
 KOTOHA_UNSUPPORTED_CONTRACT = -2,
 KOTOHA_UNSUPPORTED_CAPABILITY = -3,
 KOTOHA_INVALID_ASSET = -4,
 KOTOHA_RESOURCE_EXHAUSTED = -5,
 KOTOHA_BUSY = -6,
 KOTOHA_CANCELLED = -7,
 KOTOHA_INTERNAL_ERROR = -8,
 KOTOHA_INVALID_STATE = -9
};

typedef struct {
 uint32_t struct_size;
 uint32_t max_compute_threads;
 uint64_t memory_budget_bytes;
 uint64_t control_message_budget_bytes;
 uint64_t event_queue_budget_bytes;
 uint64_t reserved[4]; /* Initialized to zero. */
} kotoha_runtime_config;

typedef struct {
 uint32_t struct_size;
 uint32_t reserved;
 const uint8_t *json_utf8;
 uint64_t json_length;
} kotoha_control_request;

/* Audio workers submit finite, interleaved float samples.
 * Frame count, sample count multiplication, buffer length and timestamps are checked.
 * The runtime copies accepted frames before return.
 */
typedef struct {
 uint32_t struct_size;
 uint32_t sample_rate;
 uint32_t channels;
 uint32_t reserved;
 const float *samples;
 uint64_t frame_count;
 uint64_t sample_count;
 uint64_t timestamp_microseconds;
} kotoha_audio_chunk;

KOTOHA_API kotoha_status kotoha_runtime_create(
 const kotoha_runtime_config *config, kotoha_runtime **out_runtime);
KOTOHA_API kotoha_status kotoha_capabilities(
 kotoha_runtime *runtime, uint8_t *output, uint64_t capacity,
 uint64_t *required_length);
/* The broker registers verified assets and exposes scoped read-only references.
 * The descriptor names those references, an adapter and required capabilities.
 */
KOTOHA_API kotoha_status kotoha_engine_create(
 kotoha_runtime *runtime, const kotoha_control_request *descriptor,
 kotoha_engine **out_engine);
KOTOHA_API kotoha_status kotoha_submit(
 kotoha_engine *engine, const kotoha_control_request *request,
 kotoha_job **out_job);
KOTOHA_API kotoha_status kotoha_submit_audio(
 kotoha_job *job, const kotoha_audio_chunk *chunk);
KOTOHA_API kotoha_status kotoha_finish_input(kotoha_job *job);
/* One consumer owns polling. required_length is the UTF-8 byte count.
 * A small output buffer preserves the queued event and reports the required size.
 * Partial events may coalesce. Committed results and the terminal event are durable
 * within the negotiated queue/backpressure contract.
 */
KOTOHA_API kotoha_status kotoha_poll_event(
 kotoha_job *job, uint32_t timeout_ms, uint8_t *output,
 uint64_t capacity, uint64_t *required_length);
/* cancel is thread-safe and idempotent while the handle remains alive. */
KOTOHA_API kotoha_status kotoha_cancel(kotoha_job *job);
/* Destruction requires terminal, drained work and exclusive handle ownership.
 * BUSY preserves the handle. Successful destruction consumes it.
 */
KOTOHA_API kotoha_status kotoha_job_destroy(kotoha_job *job);
KOTOHA_API kotoha_status kotoha_engine_destroy(kotoha_engine *engine);
KOTOHA_API kotoha_status kotoha_runtime_destroy(kotoha_runtime *runtime);
#ifdef __cplusplus
}
#endif
#endif
