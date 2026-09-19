# CloudWatch alarms and SNS email notifications

This lab exercises an alert and recovery path using a custom metric, a CloudWatch
alarm and an SNS email subscription. The signal is published manually by a script;
it does not represent real application errors or monitor an existing service.

## Configuration

| Setting | Value |
| --- | --- |
| Namespace / metric | Portfolio/MonitoringLab / DemoSignal |
| Dimension | Lab = portfolio-monitoring-lab |
| Evaluation | Maximum over 60 seconds; one breaching period |
| Alarm condition | Greater than 1 |
| Test signal | 5 for ALARM; 0 for OK |
| Missing data | missing; can eventually lead to INSUFFICIENT_DATA |
| Notifications | Both ALARM and OK transitions |

Terraform manages three resources: the SNS topic, its policy and the alarm.
The AWS CLI requests the email subscription after deployment, and the recipient
confirms it in email. The topic policy limits CloudWatch publishing to this alarm
and account. Deleting the topic removes its subscriptions.

## Deploy and confirm

Use Git Bash with AWS CLI v2 credentials and Terraform >=1.6,<2.0. The identity
needs permissions for SNS, CloudWatch alarms and metric publishing. No Docker,
EC2 or application deployment is needed. Alarm, custom metric and SNS usage may
incur charges.

```bash
bash lab.sh deploy
```

Review the Terraform plan and type `deploy`. Enter your own notification email
when asked. It is saved in an ignored local file, not in Terraform variables or
outputs. Open the AWS Notifications email and click **Confirm subscription**.

```bash
bash lab.sh subscription
```

If deployment succeeded but subscription creation failed, use `bash lab.sh subscribe`.
Do not share confirmation or unsubscribe links in screenshots.

## Exercise the alert path

First establish a normal baseline:

```bash
bash lab.sh recover
```

Then trigger an alarm:

```bash
bash lab.sh trigger
```

Check the ALARM email and capture the alarm state before continuing. Recover:

```bash
bash lab.sh recover
bash lab.sh history
```

Check the OK notification. Each command publishes real metric samples every
30 seconds until the requested state is observed, with a ten-minute timeout.
The script does not force alarm state with SetAlarmState. Changes may take a few
minutes, particularly when a new metric first appears. It reports state changes
but cannot prove email delivery; verify that in your inbox. When the target state
already exists, no new transition or notification is expected.

Metric publication stops when the command exits. The alarm may later become
INSUFFICIENT_DATA. This is intentional; absent samples are not treated as healthy.
If a command times out, inspect `bash lab.sh status` and `bash lab.sh history`.

## Verified results

- SNS email subscription confirmed.
- Metric evaluation produced INSUFFICIENT_DATA → OK → ALARM → OK.
- Alarm history recorded successful SNS notification actions.
- Inbox delivery of ALARM and OK emails has not been verified.
- Cleanup succeeded: all three Terraform resources were destroyed.
- Provider checksums include Windows and Linux.

## Troubleshooting

The alarm initially remained in INSUFFICIENT_DATA because the published
metric dimensions did not match the alarm. Changing the AWS CLI
put-metric-data argument to `--dimensions Lab=portfolio-monitoring-lab`
resolved the issue. Subsequent alarm and recovery checks passed.

## Cleanup

```bash
bash lab.sh delete
```

Review the plan and type `delete`. Keep this folder and its Terraform state until
cleanup finishes. Alarm and SNS resources are removed. CloudWatch custom metric
history cannot be deleted manually; it expires according to AWS retention.
The script stops publishing samples when trigger/recover finishes.

## Publishing

Keep source and the generated `.terraform.lock.hcl` in Git. Never publish local
Terraform states, saved plans or `.lab-*` files. Before publishing, prepare the
lock file for both Windows and Linux:

```bash
terraform providers lock -platform=windows_amd64 -platform=linux_amd64
```

## References

- [CloudWatch alarm notifications](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Notify_Users_Alarm_Changes.html)
- [Publishing custom metrics](https://docs.aws.amazon.com/cli/latest/reference/cloudwatch/put-metric-data.html)
