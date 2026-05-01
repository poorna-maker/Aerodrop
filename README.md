# Aero Drop 🚀

**Aero Drop** is a high-performance, cross-platform P2P file sharing and clipboard synchronization tool built with Flutter. It allows for seamless, secure, and blazing-fast data transfer between devices on the same local network without relying on cloud servers.

---

## ✨ Key Features

- **Instant P2P Discovery:** Automatically find nearby devices using mDNS (Multicast DNS) and NSD (Network Service Discovery). No manual IP entry required.
- **Blazing Fast TCP Transfers:** Leverages raw TCP sockets for high-speed multi-file transfers.
- **Resumable Transfers:** Intelligently detects interrupted transfers and resumes from where it left off, saving time and bandwidth.
- **Batch File Sharing:** Send entire collections of files in a single session.
- **Cross-Device Clipboard Sync:** Instantly sync text and links between your mobile and desktop devices.
- **QR Code Pairing:** Quick-connect feature for environments where mDNS might be restricted.
- **Privacy-Centric:** All data remains on your local network. No middleman, no cloud, no tracking.
- **Modern "Liquid" UI:** A beautiful, organic interface with fluid animations that makes discovery feel alive.

---

## 🛠 Tech Stack

- **Framework:** [Flutter](https://flutter.dev/) (Multi-platform support)
- **State Management:** [Riverpod](https://riverpod.dev/) for robust and reactive state handling.
- **Networking:**
  - `nsd` for zero-configuration networking.
  - `dart:io` Sockets for low-level TCP communication.
- **Hardware Integration:**
  - `device_info_plus` for unique device identification.
  - `mobile_scanner` & `qr_flutter` for QR-based discovery.
- **Platform Features:**
  - `receive_sharing_intent` for system-level "Share to" support.
  - `media_scanner` to ensure transferred images/videos appear instantly in your gallery (Android).

---

## 💎 What Makes Aero Drop Unique?

### 1. **True Platform Independence**
Unlike AirDrop (Apple only) or Nearby Share (primarily Android/Windows), Aero Drop is built on Flutter. This means it can bridge the gap between **all** platforms: iOS to Windows, Linux to Android, and MacOS to Web.

### 2. **Resume Capabilities**
Most P2P tools fail if the connection drops. Aero Drop calculates checksums and file offsets to resume partial transfers, making it reliable for large video files or zip archives.

### 3. **The "Liquid" Discovery Experience**
We moved away from boring lists. The "Liquid Ring" UI provides an organic, radar-like experience that visualizes the discovery process, making it intuitive and visually engaging.

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK installed.
- Devices must be on the same Wi-Fi network.

### Running the App
1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/aero-drop.git
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application:
   ```bash
   flutter run
   ```

---

## 📖 How It Works

1. **Broadcasting:** When you open the app, it starts broadcasting its presence using a service type `_aerodrop._tcp`.
2. **Scanning:** Other devices on the network listen for this specific service.
3. **Handshake:** When you select a device to send to, a control handshake is sent via TCP to request permission.
4. **Data Drain:** Upon acceptance, the receiving device opens a "Data Drain" (TCP Server) and the sender streams the files in chunks.
5. **Validation:** Both devices verify the file sizes and move the `.part` files to the final destination.


