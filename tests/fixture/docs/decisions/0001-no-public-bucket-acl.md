---
edr: 1
id: 01M6C7Q3Y8R5T2V9W4X6Z0A1B3
slug: no-public-bucket-acl
title: "S3 buckets have no public ACL"
status: accepted
owner: team:platform
scope:
  - org: example
valid_from: 2026-01-01
valid_to: null
review_by: 2030-01-01
supersedes: []
criticality: blocking
checks:
  - engine: opa
    target: terraform-plan
    ref: ipso:aws/s3-no-public-acl
waivers: []
sources:
  - type: pr
    url: https://github.com/ipsofacto-io/ipso-action/pull/1
tags: [storage]
---

# S3 buckets have no public ACL

## Context

A public bucket ACL exposes every object in the bucket.

## Decision

No S3 bucket uses a public ACL.

## Alternatives considered

- Review every bucket by hand: a plan check runs on every change.

## Consequences

A public website needs a reviewed exception.

## Verification

The check runs on every Terraform plan.
