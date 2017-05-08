# manifest-tester

## Signierung der Firmware:
Vor dem Ausrollen kann das bereits unterschriebene neue Manifest hiermit auf Gültigkeit der Unterschriften geprüft werden.
Es prüft:
1. Jede einzelen Signatur auf Gültigkeit
2. Ob die Gesamtzahl der nötigen Signaturen für den Branch erreicht ist.

## Installation  und Vorraussetzungen
- Dieses lua-Skript muss auf einen FFTR-Router kopiert werden
- Die Kopie auf dem Knoten muss ausführbar sein ( chmod +x)
- der zu prüfende Branch (stable, experimental, beta, ..) muss auf dem Knoten mit eincompiliert sein (aus site.conf)  
- die zu prüfenden Unterschriften müssen mit einem PublicKey auf dem Knoten in dem zu prüfenden Branch vertreten sein.
- ist kein Branch explizit angegeben, dann wird der Branch angenommen, der auf dem FF-Knoten selbst installiert ist
- das Manifest muss per IPv6 und http:// mit wget erreichbar sein. (eine IPv4 hat der Knoten nicht und "https://" kann wget nicht)  
hier bietet sich also unser Mirror zu github an oder ein eigener Server der per IPv6 erreichbar ist.
- Die Namenskonvention für den Dateinmane des Manifestes ist:  
für Branch 'stable': stable.manifest  
für Branch 'beta': beta.manifest  

## Das Tool kann einen Pfad auf das zu prüfende Manifest erhalten.  
Nicht immer ist das zu prüfende Manifest schon im standard Updateverzeichnis des Branchs, sondern liegt noch abseits.  
Auch dieses abseits liegende Manifest kann geprüft werden.  
z.B.: 1.updates.services.fftr/firmware/tackin_test_for_next_stable_release/sysupgrade

**Aufruf:** .\/manifest-tester.lua -m 1.updates.services.fftr/firmware/tackin_test_for_next_stable_release/sysupgrade  
prüft z.B. die Datei http://1.updates.services.fftr/firmware/tackin_test_for_next_stable_release/sysupgrade/stable.manifest  
auf: 
- Vorgaben des "stable" Branches (hinterlegte Public-Keys und hinterlegte Mindestzahl an gültigen Unterschriften)
- im neuen Manifest tatsächlich gefundene Unterschriften
- Gültigkeit der gefunden Unterschriften
- Mindestanzahl der gültigen Unterschriften für den branch erreicht?

