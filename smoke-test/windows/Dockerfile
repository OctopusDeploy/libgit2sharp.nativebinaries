# Bare Windows: nanoserver ships the UCRT but NOT the VC++ Redistributable,
# so it is the clean-VM analogue for MD-2027.
FROM mcr.microsoft.com/windows/nanoserver:ltsc2022
COPY native/ C:/native/
COPY loader.exe C:/loader.exe
ENTRYPOINT ["C:\\loader.exe"]
