#include "IPV4.h"
#include <WinSock2.h>
#include <iphlpapi.h>
#include <ws2tcpip.h>

bool needInit = true;

bool initNet()
{
	if (!needInit)
		return true;

	WSAData wsaData;
	WSAStartup(0, &wsaData); // get version
	
	// load specific winsock version
	if (WSAStartup(wsaData.wHighVersion, &wsaData) == 0)
	{
		uint16_t v = wsaData.wHighVersion;
		println("[Radio] Loaded winsock v%d.%d", (int)(v >> 8), (int)(v & 0xff));
		return true;
	}
	println("[Radio] Winsock failed to load");
	needInit = false;
	return false;
}

void netStop()
{
	WSACleanup();
}

void print_adapter(PIP_ADAPTER_ADDRESSES aa)
{
	char buf[BUFSIZ];
	memset(buf, 0, BUFSIZ);
	WideCharToMultiByte(CP_ACP, 0, aa->FriendlyName, wcslen(aa->FriendlyName), buf, BUFSIZ, NULL, NULL);
	println("[Radio] adapter_name: %s", buf);
}

// https://gist.github.com/yoggy/1241986
IPV4 getLocalIP()
{
	int flags = 0;
	DWORD size;
	PIP_ADAPTER_ADDRESSES adapter_addresses, aa;
	PIP_ADAPTER_UNICAST_ADDRESS ua;

	int ret = GetAdaptersAddresses(AF_INET, flags, NULL, NULL, &size);
	if (ret != ERROR_BUFFER_OVERFLOW) 
	{
		fprintf(stderr, "Initial GetAdaptersAddresses() failed...");
		return IPV4();
	}
	adapter_addresses = (PIP_ADAPTER_ADDRESSES)malloc(size);

	ret = GetAdaptersAddresses(AF_INET, flags, NULL, adapter_addresses, &size);
	if (ret != 0) 
	{
		fprintf(stderr, "GetAdaptersAddresses() failed...");
		return IPV4();
	}

	bool found = false;
	IPV4 pick;
	for (aa = adapter_addresses; aa != NULL; aa = aa->Next) {
		//print_adapter(aa);
		for (ua = aa->FirstUnicastAddress; ua != NULL; ua = ua->Next) 
		{
			char buf[BUFSIZ];
			memset(buf, 0, BUFSIZ);
			getnameinfo(ua->Address.lpSockaddr, ua->Address.iSockaddrLength, buf, sizeof(buf), NULL, 0,NI_NUMERICHOST);
			IPV4 addr(buf);
			if (addr == IPV4(127,0,0,1)) // ignore the loop-back address
				continue;
			else if (!found)
			{
				found = true;
				pick = addr;
				println("[Radio] Lets use " + addr.getString());
			}
			else
			{
				if (pick.b1 == 169) // indicates that windows can't find a DCHP server to get an address from
					pick = addr;
				else if (addr != pick)
					println("[Radio] Multiple local addresses found! Ignoring %s", addr.getString().c_str());
			}
		}
	}

	free(adapter_addresses);

	return pick;
}