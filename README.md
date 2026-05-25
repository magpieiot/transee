# Transee: High-Performance, Privacy-First ASR for macOS

![License](https://img.shields.io/github/license/magpieiot/transee)
![Platform](https://img.shields.io/badge/platform-macOS%2015.0+-blue)
![Swift](https://img.shields.io/badge/Swift-6.3+-orange)

**Transee** is an open-source, automatic Speech Recognition (ASR) application built exclusively for macOS. Powered by OpenAI’s revolutionary **Whisper** models, Transee brings industry-leading transcription accuracy directly to your desktop—without ever sending a single byte of data to the cloud.

In an era where voice data is often treated as a commodity by large corporations, Transee stands for a different philosophy: **Your voice is your own.** By leveraging the power of Apple Silicon, Transee provides a seamless, local, and lightning-fast transcription experience that respects your privacy.

---

## 🌟 Why Transee?

Most transcription services today are cloud-based, requiring expensive subscriptions and raising significant privacy concerns. For researchers, journalists, developers, and creators, the choice is often between "free but insecure" or "secure but expensive."

Transee breaks this trade-off. It is:
- **100% Local:** All processing happens on your Mac. No API keys, no internet connection required, and no hidden data logging.
- **Native Experience:** Built with SwiftUI for a sleek, modern, and lightweight macOS experience.
- **Optimized Performance:** Optimized for Apple Silicon (M1/M2/M3) using Core ML and Metal to ensure minimal battery drain and maximum speed.

---

## 🚀 Key Features

### 1. Powered by OpenAI Whisper
Transee supports the full range of Whisper model sizes (Tiny, Base, Small, Medium, Large). Whether you need a lightning-fast summary or a near-perfect academic transcription, you can swap models with a single click.

### 2. Multi-Format Transcription
Transcribe audio and video files into various formats tailored for your needs:
- **Plain Text (.txt):** For quick notes and documentation.
- **Subtitles (.srt):** Perfectly timed captions for video editors and content creators.
- **Rich JSON:** For developers who want to integrate the output into other workflows.

### 3. Real-time Live Review
Not only can you preview the transcription results in real-time when transcribing files, but you can also capture live audio from your microphone. It is perfect for meetings, lectures, or live coding sessions.

### 4. Advanced Multilingual Support
Whisper is trained on 680,000 hours of multilingual and multitask supervised data. Transee inherits this power, allowing you to transcribe and translate over 90 languages with high robustness to accents and background noise.

### 5. Intuitive UX/UI
- **Drag & Drop:** Simply drop your media files into the app to start transcribing.
- **Batch Processing:** Handle multiple files simultaneously to save time.

---

## 🛠 Technical Architecture

Transee is more than just a wrapper. It is an optimized implementation designed to squeeze every bit of performance out of macOS:

- **Core ML & Metal:** Instead of running heavy Python environments, Transee utilizes `whisper.cpp` and Core ML models. This allows the app to utilize the **Neural Engine** and **GPU**, keeping the CPU cool and the fans silent.
- **SwiftUI & Combine:** The UI is reactive and modern, ensuring the interface remains responsive even during heavy inference tasks.
- **Sandbox Security:** The app operates within the strict macOS Sandbox environment, ensuring it only accesses the files and hardware (like the microphone) that you explicitly permit.

---

## 📦 Installation

As an open-source project, you can get started in two ways:

### Method 1: Download the Binary
Visit the [Releases](https://github.com/magpieiot/transee/releases) page and download the latest `.dmg` or `.app` file.

### Method 2: Build from Source
If you are a developer, you can clone the repository and build it using Xcode:

```bash
git clone https://github.com/magpieiot/transee.git
cd transee
open Transee.xcodeproj
```
*Note: You will need Xcode 15.0+ and macOS 15.0+.*

---

## 🛡 Privacy by Design

Privacy isn't a feature; it's our foundation.
- **No Analytics:** We do not use Google Analytics, Firebase, or any tracking SDKs.
- **No Cloud Inference:** We do not use the OpenAI API; the "Whisper" model runs locally on your hardware.
- **Zero Data Collection:** We don't know who you are, what you transcribe, or how often you use the app.

---

## 🗺 Roadmap

- [ ] **Speaker Diarization:** Identify who is speaking in a conversation.
- [ ] **Custom Vocabulary:** Add specialized terms to improve accuracy for technical niches.
- [ ] **System Audio Loopback:** Transcribe audio directly from Zoom, Teams, or YouTube without external hardware.
- [ ] **Mobile Companion:** A companion iOS app with similar on-device capabilities.

---

## 🙏 Acknowledgements
Transee is built upon the incredible work of the open-source AI community:

WhisperKit: Special thanks to the team at Argmax for providing the high-performance Core ML implementation of Whisper that powers this app.
OpenAI Whisper: For the original model weights and groundbreaking research in ASR.

---

## 🤝 Contributing

We welcome contributions from the community! Whether it’s fixing a bug, adding a new language, or improving the UI, your help makes Transee better for everyone.

1. Fork the Project.
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`).
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the Branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

---

## 📄 License

Distributed under the **MIT License**. See `LICENSE` for more information.

## ✉️ Contact

Project Link: [https://github.com/magpieiot/transee](https://github.com/magpieiot/transee)
Developer: [magpieiot@gmail.com](mailto:magpieiot@gmail.com)

---
*Created with ❤️ for the open-source community.*
