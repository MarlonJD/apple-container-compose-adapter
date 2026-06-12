# LinuxPod Base Overhead Evidence Report

Total records: `10`

## Status Counts

- `blocked-runtime`: `7`
- `measured-with-limitations`: `3`

## Scenarios

### `idle-pod`

Records: `2`
Measured records: `1`

Statuses:
- `blocked-runtime`: `1`
- `measured-with-limitations`: `1`

Measured metrics:
- `setupSeconds`: n=`1`, min=`22.937684059143066`, p50=`22.937684059143066`, max=`22.937684059143066`
- `createSeconds`: n=`1`, min=`0.666003942489624`, p50=`0.666003942489624`, max=`0.666003942489624`
- `stopSeconds`: n=`1`, min=`0.022367000579833984`, p50=`0.022367000579833984`, max=`0.022367000579833984`
- `deleteSeconds`: n=`1`, min=`0.022360920906066895`, p50=`0.022360920906066895`, max=`0.022360920906066895`
- `processRSSBytes`: n=`1`, min=`815104`, p50=`815104`, max=`815104`
- `processHighWaterRSSBytes`: n=`1`, min=`815104`, p50=`815104`, max=`815104`
- `processCount`: n=`1`, min=`1`, p50=`1`, max=`1`
- `cgroupMemoryCurrentBytes`: n=`1`, min=`1900544`, p50=`1900544`, max=`1900544`
- `cgroupMemoryLimitBytes`: n=`1`, min=`18446744073709551615`, p50=`18446744073709551615`, max=`18446744073709551615`
- `blockReadBytes`: n=`1`, min=`1654784`, p50=`1654784`, max=`1654784`
- `blockWriteBytes`: n=`1`, min=`0`, p50=`0`, max=`0`
- `cpuUsageUsec`: n=`1`, min=`3061`, p50=`3061`, max=`3061`
- `loadCompletedWork`: n=`1`, min=`0`, p50=`0`, max=`0`
- `loadErrors`: n=`1`, min=`0`, p50=`0`, max=`0`

### `postgres-api`

Records: `6`
Measured records: `1`

Statuses:
- `blocked-runtime`: `5`
- `measured-with-limitations`: `1`

Measured metrics:
- `setupSeconds`: n=`1`, min=`76.68017196655273`, p50=`76.68017196655273`, max=`76.68017196655273`
- `createSeconds`: n=`1`, min=`0.45767295360565186`, p50=`0.45767295360565186`, max=`0.45767295360565186`
- `readinessSeconds`: n=`1`, min=`1.0829960107803345`, p50=`1.0829960107803345`, max=`1.0829960107803345`
- `loadSeconds`: n=`1`, min=`0.0447770357131958`, p50=`0.0447770357131958`, max=`0.0447770357131958`
- `stopSeconds`: n=`1`, min=`0.12905800342559814`, p50=`0.12905800342559814`, max=`0.12905800342559814`
- `deleteSeconds`: n=`1`, min=`0.12904798984527588`, p50=`0.12904798984527588`, max=`0.12904798984527588`
- `processRSSBytes`: n=`1`, min=`28688384`, p50=`28688384`, max=`28688384`
- `processHighWaterRSSBytes`: n=`1`, min=`28688384`, p50=`28688384`, max=`28688384`
- `processCount`: n=`1`, min=`13`, p50=`13`, max=`13`
- `cgroupMemoryCurrentBytes`: n=`1`, min=`143790080`, p50=`143790080`, max=`143790080`
- `cgroupMemoryPeakBytes`: n=`1`, min=`155275264`, p50=`155275264`, max=`155275264`
- `dbDataFootprintBytes`: n=`1`, min=`40366080`, p50=`40366080`, max=`40366080`
- `blockReadBytes`: n=`1`, min=`78618624`, p50=`78618624`, max=`78618624`
- `blockWriteBytes`: n=`1`, min=`40763392`, p50=`40763392`, max=`40763392`
- `cpuUsageUsec`: n=`1`, min=`445532`, p50=`445532`, max=`445532`
- `loadCompletedWork`: n=`1`, min=`1`, p50=`1`, max=`1`
- `loadErrors`: n=`1`, min=`0`, p50=`0`, max=`0`

### `postgres-only`

Records: `2`
Measured records: `1`

Statuses:
- `blocked-runtime`: `1`
- `measured-with-limitations`: `1`

Measured metrics:
- `setupSeconds`: n=`1`, min=`90.2369270324707`, p50=`90.2369270324707`, max=`90.2369270324707`
- `createSeconds`: n=`1`, min=`0.4377000331878662`, p50=`0.4377000331878662`, max=`0.4377000331878662`
- `readinessSeconds`: n=`1`, min=`1.096068024635315`, p50=`1.096068024635315`, max=`1.096068024635315`
- `loadSeconds`: n=`1`, min=`0.04070591926574707`, p50=`0.04070591926574707`, max=`0.04070591926574707`
- `stopSeconds`: n=`1`, min=`0.10085999965667725`, p50=`0.10085999965667725`, max=`0.10085999965667725`
- `deleteSeconds`: n=`1`, min=`0.10085105895996094`, p50=`0.10085105895996094`, max=`0.10085105895996094`
- `processRSSBytes`: n=`1`, min=`27856896`, p50=`27856896`, max=`27856896`
- `processHighWaterRSSBytes`: n=`1`, min=`27856896`, p50=`27856896`, max=`27856896`
- `processCount`: n=`1`, min=`6`, p50=`6`, max=`6`
- `cgroupMemoryCurrentBytes`: n=`1`, min=`130813952`, p50=`130813952`, max=`130813952`
- `cgroupMemoryLimitBytes`: n=`1`, min=`18446744073709551615`, p50=`18446744073709551615`, max=`18446744073709551615`
- `dbDataFootprintBytes`: n=`1`, min=`40366080`, p50=`40366080`, max=`40366080`
- `blockReadBytes`: n=`1`, min=`67395584`, p50=`67395584`, max=`67395584`
- `blockWriteBytes`: n=`1`, min=`40755200`, p50=`40755200`, max=`40755200`
- `cpuUsageUsec`: n=`1`, min=`493887`, p50=`493887`, max=`493887`
- `loadCompletedWork`: n=`1`, min=`1`, p50=`1`, max=`1`
- `loadErrors`: n=`1`, min=`0`, p50=`0`, max=`0`
