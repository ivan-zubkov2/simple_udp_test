#define _WINSOCK_DEPRECATED_NO_WARNINGS

#include <winsock2.h>
#include <ws2tcpip.h>

#include <chrono>
#include <cstdlib>
#include <ctime>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>

#pragma comment(lib, "ws2_32.lib")

namespace {

struct Message {
  int id;
  std::string time;
  std::string text;
};

void PrintUsage() {
  std::cout << "Usage: client.exe <target_ip> <port> [message]\n";
  std::cout << "Example: client.exe 127.0.0.1 9000 hello\n";
}

void ThrowLastSocketError(const std::string& context) {
  std::ostringstream stream;
  stream << context << " failed with WSA error " << WSAGetLastError();
  throw std::runtime_error(stream.str());
}

int ParsePort(const char* value) {
  char* end = nullptr;
  const long port = std::strtol(value, &end, 10);
  if (end == value || *end != '\0' || port < 1 || port > 65535) {
    throw std::invalid_argument("Port must be between 1 and 65535.");
  }
  return static_cast<int>(port);
}

std::string EscapeJson(const std::string& value) {
  std::ostringstream stream;
  for (const char character : value) {
    switch (character) {
      case '\\':
        stream << "\\\\";
        break;
      case '"':
        stream << "\\\"";
        break;
      case '\n':
        stream << "\\n";
        break;
      case '\r':
        stream << "\\r";
        break;
      case '\t':
        stream << "\\t";
        break;
      default:
        stream << character;
        break;
    }
  }
  return stream.str();
}

std::string CurrentTimestamp() {
  const auto now = std::chrono::system_clock::now();
  const auto milliseconds =
      std::chrono::duration_cast<std::chrono::milliseconds>(
          now.time_since_epoch()) %
      1000;

  const std::time_t currentTime = std::chrono::system_clock::to_time_t(now);
  std::tm localTime = {};
  localtime_s(&localTime, &currentTime);

  std::ostringstream stream;
  stream << std::put_time(&localTime, "%Y-%m-%dT%H:%M:%S") << '.'
         << std::setw(3) << std::setfill('0') << milliseconds.count();
  return stream.str();
}

std::string ToWire(const Message& message) {
  std::ostringstream stream;
  stream << "{\"id\":" << message.id << ",\"time\":\"" << message.time
         << "\",\"message\":\"" << EscapeJson(message.text) << "\"}";
  return stream.str();
}

}  // namespace

int main(int argc, char* argv[]) {
  if (argc < 3 || argc > 4) {
    PrintUsage();
    return 1;
  }

  try {
    const std::string targetIp = argv[1];
    const int port = ParsePort(argv[2]);
    const std::string messageText = argc == 4 ? argv[3] : "Hello from client";

    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
      ThrowLastSocketError("WSAStartup");
    }

    SOCKET socketHandle = INVALID_SOCKET;

    try {
      socketHandle = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
      if (socketHandle == INVALID_SOCKET) {
        ThrowLastSocketError("socket");
      }

      u_long nonBlocking = 1;
      if (ioctlsocket(socketHandle, FIONBIO, &nonBlocking) == SOCKET_ERROR) {
        ThrowLastSocketError("ioctlsocket(FIONBIO)");
      }

      sockaddr_in targetAddress = {};
      targetAddress.sin_family = AF_INET;
      targetAddress.sin_port = htons(static_cast<u_short>(port));

      if (InetPtonA(AF_INET, targetIp.c_str(), &targetAddress.sin_addr) != 1) {
        throw std::invalid_argument("Invalid IPv4 address: " + targetIp);
      }

      int nextId = 0;
      constexpr auto sendInterval = std::chrono::milliseconds(5);

      std::cout << "Sending UDP datagrams to " << targetIp << ':' << port
                << std::endl;

      while (true) {
        const auto tickStarted = std::chrono::steady_clock::now();

        for (int index = 0; index < 4; ++index) {
          const Message message{
              nextId++,
              CurrentTimestamp(),
              messageText,
          };

          const std::string payload = ToWire(message);
          int failedAttempts = 0;

          while (true) {
            const int bytesSent =
                sendto(socketHandle, payload.data(),
                       static_cast<int>(payload.size()), 0,
                       reinterpret_cast<sockaddr*>(&targetAddress),
                       sizeof(targetAddress));

            if (bytesSent > 0) {
              if (failedAttempts > 0) {
                std::cout << "Retry succeeded for id=" << message.id
                          << " after " << failedAttempts << " failure(s)"
                          << std::endl;
              }
//
//              std::cout << "Sent id=" << message.id << " time=" << message.time
//                        << " message=\"" << message.text << '"' << std::endl;
              break;
            }

            ++failedAttempts;
            std::cout << "Failed to send id=" << message.id << " to "
                      << targetIp << ':' << port << "; retry attempt "
                      << failedAttempts << " (WSA error "
                      << WSAGetLastError() << ')' << std::endl;
          }
        }

        const auto elapsed = std::chrono::steady_clock::now() - tickStarted;
        if (elapsed < sendInterval) {
          std::this_thread::sleep_for(sendInterval - elapsed);
        }
      }
    } catch (...) {
      if (socketHandle != INVALID_SOCKET) {
        closesocket(socketHandle);
      }
      WSACleanup();
      throw;
    }
  } catch (const std::exception& error) {
    std::cerr << error.what() << std::endl;
    WSACleanup();
    return 1;
  }

  return 0;
}
