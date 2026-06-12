# LinuxPod Base Overhead Evidence Report

Total records: `3`

## Status Counts

- `measured-with-limitations`: `3`

## Scenarios

### `idle-pod`

Records: `1`
Measured records: `1`

Statuses:
- `measured-with-limitations`: `1`

Measured metrics:
- `setupSeconds`: n=`1`, min=`11.293304085731506`, p50=`11.293304085731506`, max=`11.293304085731506`
- `createSeconds`: n=`1`, min=`0.4283900260925293`, p50=`0.4283900260925293`, max=`0.4283900260925293`
- `stopSeconds`: n=`1`, min=`0.03785300254821777`, p50=`0.03785300254821777`, max=`0.03785300254821777`
- `deleteSeconds`: n=`1`, min=`0.03784501552581787`, p50=`0.03784501552581787`, max=`0.03784501552581787`
- `processRSSBytes`: n=`1`, min=`811008`, p50=`811008`, max=`811008`
- `processHighWaterRSSBytes`: n=`1`, min=`811008`, p50=`811008`, max=`811008`
- `processCount`: n=`1`, min=`1`, p50=`1`, max=`1`
- `cgroupMemoryCurrentBytes`: n=`1`, min=`1900544`, p50=`1900544`, max=`1900544`
- `cgroupMemoryLimitBytes`: n=`1`, min=`18446744073709551615`, p50=`18446744073709551615`, max=`18446744073709551615`
- `hostRuntimeRSSBytes`: n=`1`, min=`50266112`, p50=`50266112`, max=`50266112`
- `blockReadBytes`: n=`1`, min=`1654784`, p50=`1654784`, max=`1654784`
- `blockWriteBytes`: n=`1`, min=`0`, p50=`0`, max=`0`
- `cpuUsageUsec`: n=`1`, min=`5193`, p50=`5193`, max=`5193`
- `loadCompletedWork`: n=`1`, min=`0`, p50=`0`, max=`0`
- `loadErrors`: n=`1`, min=`0`, p50=`0`, max=`0`

### `postgres-api`

Records: `1`
Measured records: `1`

Statuses:
- `measured-with-limitations`: `1`

Measured metrics:
- `setupSeconds`: n=`1`, min=`180.16567206382751`, p50=`180.16567206382751`, max=`180.16567206382751`
- `createSeconds`: n=`1`, min=`0.5390769243240356`, p50=`0.5390769243240356`, max=`0.5390769243240356`
- `readinessSeconds`: n=`1`, min=`1.112070918083191`, p50=`1.112070918083191`, max=`1.112070918083191`
- `loadSeconds`: n=`1`, min=`0.051051974296569824`, p50=`0.051051974296569824`, max=`0.051051974296569824`
- `stopSeconds`: n=`1`, min=`0.13427996635437012`, p50=`0.13427996635437012`, max=`0.13427996635437012`
- `deleteSeconds`: n=`1`, min=`0.13426995277404785`, p50=`0.13426995277404785`, max=`0.13426995277404785`
- `processRSSBytes`: n=`1`, min=`28708864`, p50=`28708864`, max=`28708864`
- `processHighWaterRSSBytes`: n=`1`, min=`28708864`, p50=`28708864`, max=`28708864`
- `processCount`: n=`1`, min=`13`, p50=`13`, max=`13`
- `cgroupMemoryCurrentBytes`: n=`1`, min=`144023552`, p50=`144023552`, max=`144023552`
- `cgroupMemoryPeakBytes`: n=`1`, min=`155111424`, p50=`155111424`, max=`155111424`
- `hostRuntimeRSSBytes`: n=`1`, min=`37404672`, p50=`37404672`, max=`37404672`
- `dbDataFootprintBytes`: n=`1`, min=`40366080`, p50=`40366080`, max=`40366080`
- `blockReadBytes`: n=`1`, min=`78753792`, p50=`78753792`, max=`78753792`
- `blockWriteBytes`: n=`1`, min=`40775680`, p50=`40775680`, max=`40775680`
- `cpuUsageUsec`: n=`1`, min=`563247`, p50=`563247`, max=`563247`
- `loadCompletedWork`: n=`1`, min=`1`, p50=`1`, max=`1`
- `loadErrors`: n=`1`, min=`0`, p50=`0`, max=`0`

### `postgres-only`

Records: `1`
Measured records: `1`

Statuses:
- `measured-with-limitations`: `1`

Measured metrics:
- `setupSeconds`: n=`1`, min=`62.356486082077026`, p50=`62.356486082077026`, max=`62.356486082077026`
- `createSeconds`: n=`1`, min=`0.46560001373291016`, p50=`0.46560001373291016`, max=`0.46560001373291016`
- `readinessSeconds`: n=`1`, min=`1.0999689102172852`, p50=`1.0999689102172852`, max=`1.0999689102172852`
- `loadSeconds`: n=`1`, min=`0.05616497993469238`, p50=`0.05616497993469238`, max=`0.05616497993469238`
- `stopSeconds`: n=`1`, min=`0.10044491291046143`, p50=`0.10044491291046143`, max=`0.10044491291046143`
- `deleteSeconds`: n=`1`, min=`0.10043203830718994`, p50=`0.10043203830718994`, max=`0.10043203830718994`
- `processRSSBytes`: n=`1`, min=`27930624`, p50=`27930624`, max=`27930624`
- `processHighWaterRSSBytes`: n=`1`, min=`27930624`, p50=`27930624`, max=`27930624`
- `processCount`: n=`1`, min=`6`, p50=`6`, max=`6`
- `cgroupMemoryCurrentBytes`: n=`1`, min=`131137536`, p50=`131137536`, max=`131137536`
- `cgroupMemoryLimitBytes`: n=`1`, min=`18446744073709551615`, p50=`18446744073709551615`, max=`18446744073709551615`
- `hostRuntimeRSSBytes`: n=`1`, min=`38191104`, p50=`38191104`, max=`38191104`
- `dbDataFootprintBytes`: n=`1`, min=`40366080`, p50=`40366080`, max=`40366080`
- `blockReadBytes`: n=`1`, min=`67395584`, p50=`67395584`, max=`67395584`
- `blockWriteBytes`: n=`1`, min=`40771584`, p50=`40771584`, max=`40771584`
- `cpuUsageUsec`: n=`1`, min=`558741`, p50=`558741`, max=`558741`
- `loadCompletedWork`: n=`1`, min=`1`, p50=`1`, max=`1`
- `loadErrors`: n=`1`, min=`0`, p50=`0`, max=`0`
