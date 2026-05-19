#define _WINSOCK_DEPRECATED_NO_WARNINGS

#include <winsock2.h>
#include <ws2tcpip.h>

#include <cstdlib>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>

#pragma comment(lib, "ws2_32.lib")

namespace {

struct Message {
  int id;
  std::string time;
  std::string text;
};

void PrintUsage() {
  std::cout << "Usage: server.exe <bind_ip> <port>\n";
  std::cout << "Example: server.exe 0.0.0.0 9000\n";
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

Message ParseMessage(const std::string& payload) {
  static const std::regex pattern(
      R"json(\{"id":([0-9]+),"time":"([^"]+)","message":"((?:\\.|[^"\\])*)"\})json");

  std::smatch match;
  if (!std::regex_match(payload, match, pattern)) {
    throw std::runtime_error("Message is not in the expected JSON format.");
  }

  std::string text = match[3].str();
  std::string unescaped;
  unescaped.reserve(text.size());

  for (std::size_t index = 0; index < text.size(); ++index) {
    const char current = text[index];
    if (current == '\\' && index + 1 < text.size()) {
      const char next = text[index + 1];
      switch (next) {
        case '\\':
        case '"':
        case '/':
          unescaped.push_back(next);
          ++index;
          continue;
        case 'n':
          unescaped.push_back('\n');
          ++index;
          continue;
        case 'r':
          unescaped.push_back('\r');
          ++index;
          continue;
        case 't':
          unescaped.push_back('\t');
          ++index;
          continue;
        default:
          break;
      }
    }
    unescaped.push_back(current);
  }

  return Message{
      std::stoi(match[1].str()),
      match[2].str(),
      unescaped,
  };
}

std::string EndpointKey(const sockaddr_in& address) {
  char ipBuffer[INET_ADDRSTRLEN] = {};
  if (InetNtopA(AF_INET, const_cast<IN_ADDR*>(&address.sin_addr), ipBuffer,
                sizeof(ipBuffer)) == nullptr) {
    std::strcpy(ipBuffer, "<invalid>");
  }

  std::ostringstream stream;
  stream << ipBuffer << ':' << ntohs(address.sin_port);
  return stream.str();
}

}  // namespace

int main(int argc, char* argv[]) {
  if (argc != 3) {
    PrintUsage();
    return 1;
  }

  try {
    const std::string bindIp = argv[1];
    const int port = ParsePort(argv[2]);

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

      sockaddr_in bindAddress = {};
      bindAddress.sin_family = AF_INET;
      bindAddress.sin_port = htons(static_cast<u_short>(port));

      if (InetPtonA(AF_INET, bindIp.c_str(), &bindAddress.sin_addr) != 1) {
        throw std::invalid_argument("Invalid IPv4 address: " + bindIp);
      }

      if (bind(socketHandle, reinterpret_cast<sockaddr*>(&bindAddress),
               sizeof(bindAddress)) == SOCKET_ERROR) {
        ThrowLastSocketError("bind");
      }

      std::cout << "UDP listener started on " << bindIp << ':' << port
                << std::endl;

      std::unordered_map<std::string, int> lastReceivedIds;
      char buffer[4096];

      while (true) {
        sockaddr_in senderAddress = {};
        int senderLength = sizeof(senderAddress);

        const int bytesReceived =
            recvfrom(socketHandle, buffer, sizeof(buffer), 0,
                     reinterpret_cast<sockaddr*>(&senderAddress), &senderLength);

        if (bytesReceived == SOCKET_ERROR) {
          ThrowLastSocketError("recvfrom");
        }

        const std::string payload(buffer, buffer + bytesReceived);
        const std::string endpoint = EndpointKey(senderAddress);

        try {
          const Message message = ParseMessage(payload);
          const auto lastIt = lastReceivedIds.find(endpoint);
          if (lastIt != lastReceivedIds.end()) {
            const int expectedId = lastIt->second + 1;
            if (message.id != expectedId) {
              std::cout << "ERROR [" << endpoint << "] expected id="
                        << expectedId << " but received id=" << message.id
                        << std::endl;
            }
          }

          lastReceivedIds[endpoint] = message.id;
          std::cout << '[' << endpoint << "] id=" << message.id
                    << " time=" << message.time << " message=\""
                    << message.text << '"' << std::endl;
        } catch (const std::exception& error) {
          std::cout << "Invalid message from " << endpoint << ": "
                    << error.what() << std::endl;
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
