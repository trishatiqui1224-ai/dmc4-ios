// Devil May Cry 4 iOS Port - Adaptive Thread QoS Management
// Ensures MT Framework worker & audio threads run at User Initiated QoS

#include <pthread.h>
#include <rex/logging.h>

namespace dmc4::qos {

void SetWorkerThreadQoS() {
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INITIATED, 0);
}

void SetAudioThreadQoS() {
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
}

} // namespace dmc4::qos
