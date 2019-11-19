AWS_PROFILE=dustbort \
aws cloudformation deploy \
  --template-file vpc.cfn.yaml \
  --stack-name vpc \
  --no-fail-on-empty-changeset \
  --tags email=dustbort@gmail.com \
  --parameter-overrides \
    EnvironmentName=dev