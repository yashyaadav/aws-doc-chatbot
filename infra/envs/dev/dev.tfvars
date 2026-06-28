# Non-secret dev values. The demo password is passed via TF_VAR_demo_password (env), not here.
# callback/logout URLs point at the deployed CloudFront distribution.
callback_urls = [
  "https://d47xudcf1qjnj.cloudfront.net/",
  "https://d47xudcf1qjnj.cloudfront.net",
]
logout_urls = [
  "https://d47xudcf1qjnj.cloudfront.net/",
  "https://d47xudcf1qjnj.cloudfront.net",
]
create_demo_user = true
alert_email      = ""
