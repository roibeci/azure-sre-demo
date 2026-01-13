---
name: adx-kql-queries
description: Execute KQL queries against Azure Data Explorer (sre_logs_db) for SRE incident investigation.
---

# ADX KQL Query Skill for SRE Demo

## Database: sre_logs_db

| Table | Description |
|-------|-------------|
| ApplicationGatewayAccessLogs | App Gateway access logs (parsed) |
| ApplicationGatewayFirewallLogs | WAF blocked/detected requests |
| ContainerLogs | AKS container logs via Fluentd |
| PerformanceMetrics | Azure resource metrics |

---

## ApplicationGatewayAccessLogs

**Key Columns:** TimeGenerated, ClientIP, HttpMethod, RequestUri, HttpStatus, ResponseTime, BackendServer, BackendResponseTime, ErrorInfo, ServerStatus, TransactionId, BackendPoolName

### High latency requests
```kql
ApplicationGatewayAccessLogs
| where TimeGenerated > ago(1h)
| where ResponseTime > 1.0
| project TimeGenerated, ClientIP, RequestUri, HttpStatus, ResponseTime, BackendServer, ErrorInfo
| order by ResponseTime desc
| take 50
```

### Error rate by backend pool
```kql
ApplicationGatewayAccessLogs
| where TimeGenerated > ago(1h)
| summarize Total = count(), Errors = countif(HttpStatus >= 500),
    ErrorRate = round(100.0 * countif(HttpStatus >= 500) / count(), 2)
    by BackendPoolName, bin(TimeGenerated, 5m)
| where ErrorRate > 0
```

### 504 timeout analysis
```kql
ApplicationGatewayAccessLogs
| where TimeGenerated > ago(1h)
| where HttpStatus == 504
| summarize Count = count(), AvgConnectTime = avg(ServerConnectTime)
    by bin(TimeGenerated, 5m), ErrorInfo, BackendServer
```

### Trace request by transaction ID
```kql
ApplicationGatewayAccessLogs
| where TransactionId == "<transaction-id>"
```

---

## ApplicationGatewayFirewallLogs

**Key Columns:** TimeGenerated, Action, RuleId, Message, ClientIP, ApplistUri

### Blocked attacks
```kql
ApplicationGatewayFirewallLogs
| where TimeGenerated > ago(1h)
| where Action == "Blocked"
| summarize AttackCount = count(), Rules = make_set(RuleId, 10) by ClientIP
| top 20 by AttackCount desc
```

---

## ContainerLogs

**Key Columns:** TimeGenerated, LogEntry, Stream, PodName, Namespace, ContainerName

### Container errors
```kql
ContainerLogs
| where TimeGenerated > ago(1h)
| where LogEntry has "error" or LogEntry has "exception"
| project TimeGenerated, Namespace, PodName, ContainerName, LogEntry
| order by TimeGenerated desc
| take 100
```

### Pod crash indicators
```kql
ContainerLogs
| where TimeGenerated > ago(1h)
| where LogEntry has "OOMKilled" or LogEntry has "CrashLoopBackOff"
| summarize Count = count() by PodName, Namespace
```

---

## Cross-Table Correlation

### Correlate AppGW errors with container issues
```kql
let appgw = ApplicationGatewayAccessLogs
| where TimeGenerated > ago(1h) | where HttpStatus >= 500
| summarize AppGWErrors = count() by bin(TimeGenerated, 1m);
let containers = ContainerLogs
| where TimeGenerated > ago(1h) | where LogEntry has "error"
| summarize ContainerErrors = count() by bin(TimeGenerated, 1m);
appgw | join kind=fullouter containers on TimeGenerated
| where AppGWErrors > 0 or ContainerErrors > 0
```

### Incident timeline
```kql
union
  (ApplicationGatewayAccessLogs | where HttpStatus >= 500 
   | project TimeGenerated, Source="AppGW", Event=strcat("HTTP ", HttpStatus)),
  (ContainerLogs | where LogEntry has "error"
   | project TimeGenerated, Source="Container", Event=PodName)
| where TimeGenerated > ago(2h)
| order by TimeGenerated asc
```

---

## Quick Reference

| Pattern | Example |
|---------|--------|
| Time filter | `where TimeGenerated > ago(1h)` |
| Word match (fast) | `where LogEntry has "error"` |
| Substring | `where Message contains "timeout"` |
| Aggregation | `summarize count() by bin(TimeGenerated, 5m)` |
| Top N | `top 10 by Count desc` |
