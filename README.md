# HelloID-Conn-Prov-Target-WinkWaves

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-WinkWaves](#helloid-conn-prov-target-winkwaves)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Supported  features](#supported--features)
  - [Getting started](#getting-started)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Field mapping](#field-mapping)
    - [Mapping](#mapping)
    - [Account Reference](#account-reference)
  - [Remarks](#remarks)
    - [Correlation on `userName`](#correlation-on-username)
    - [Retrieving accounts based on `id`](#retrieving-accounts-based-on-id)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-WinkWaves_ is a _target_ connector. _WinkWaves_ provides a set of REST API's that allow you to programmatically interact with its data.

## Supported  features

The following features are available:

| Feature                             | Supported | Actions                         | Remarks                                                      |
| ----------------------------------- | --------- | ------------------------------- | ------------------------------------------------------------ |
| **Account Lifecycle**               | ✅         | Create, Update, Enable, Disable |                                                              |
| **Permissions**                     | ✅         | -                               |                                                              |
| **Resources**                       | ❌         | -                               |                                                              |
| **Entitlement Import: Accounts**    | ❌         | -                               | Not supported because in-active accounts cannot be retrieved |
| **Entitlement Import: Permissions** | ❌         | -                               |                                                              |

## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting  | Description                        | Mandatory |
| -------- | ---------------------------------- | --------- |
| UserName | The UserName to connect to the API | Yes       |
| Token    | The Token to connect to the API    | Yes       |
| BaseUrl  | The URL to the API                 | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _WinkWaves_ to a person in _HelloID_.

| Setting                   | Value                                                        |
| ------------------------- | ------------------------------------------------------------ |
| Enable correlation        | `True`                                                       |
| Person correlation field  | `Person.Accounts.MicrosoftActiveDirectory.userPrincipalName` |
| Account correlation field | `userName`                                                   |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

### Mapping

Note that both the _create_ and _update_ lifecycle actions contain an extra layer of mapping to accomodate the SCIM user model.

### Account Reference

The account reference is populated with the property `id` property from _WinkWaves_.

## Remarks

### Correlation on `userName`

The correlation for this connector is based on the `userName` since the `externalId` is not available.

When filtering by username, no results are returned if the account is disabled (active: false). However, querying directly by id does return the account. This is problematic because, when creating a user, we first check whether an account already exists—regardless of whether it is enabled or disabled.

As a result, a new account is always created, even if an inactive one already exists. This leads to issues with uniqueness constraints on email or username, which can eventually cause data pollution and trigger errors that will need to be resolved manually.

### Retrieving accounts based on `id`

When requesting an account by `id` and the account is not found, the API returns a 404 Not Found status with an empty JSON object ({}) as the response body. As a result; ony the .NET generic 404 message will be shown in the logging. Note that this message differs depending on the PowerShell version being used.

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint | Description               |
| -------- | ------------------------- |
| /Users   | Retrieve user information |

### API documentation

API documenation is limited. For more information on SCIM, please refer to: https://simplecloud.info/

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
