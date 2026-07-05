# AI_PROJECT_CONTEXT.md

## Project Name
مجلس الرحمات العام

## Project Goal
Build a professional Flutter + Firebase system for managing councils, members, memberships, payments, receipts, rentals, notifications, roles, and future AI/OCR features.

## Current Stack
- Flutter
- Firebase Authentication
- Cloud Firestore
- Firebase Storage
- Riverpod
- GoRouter
- Android / Huawei support
- Arabic first, English support planned

## Core Architecture Rule
This is not only one council app. Build it as a scalable platform that can support multiple councils later.

## Main Entities
- users: real person account
- organizations: councils
- memberships: link between user and council
- payments: required payments/subscriptions/rentals
- transactions: receipt submissions and reviews
- membership_requests: requests to join a council
- rentals: hall/council rental requests
- roles: permission roles
- audit_logs: every admin action
- notifications_queue: notifications to send

## Users and Memberships
A user has one account using phone/civil ID.
A user can belong to one or more organizations through memberships.

If user has one membership: enter directly.
If user has multiple memberships: show organization selector.
If user has no approved membership: show pending/request screen.

## Registration Rule
No user can join a council directly.
User creates account, then requests to join an organization.
Admin must approve membership_request before access is allowed.

## Roles
Do not rely only on isAdmin.
Use role-based access:
- superAdmin
- chairman
- financialManager
- financialReviewer
- secretary
- member

## Financial System
Payments must support:
- monthly
- annual
- rental
- custom

Payments must support:
- amountDue
- amountPaid
- remainingAmount
- organizationId
- memberId
- paidByMemberId
- paidForMemberIds
- receiptUrl
- transactionId
- review fields

## Receipt / Transaction System
Transactions must support:
- receipt image/pdf
- submittedAmount
- OCR fields later:
  - ocrAmount
  - ocrBank
  - ocrReference
  - ocrDate
  - ocrAccountNumber
  - aiConfidence
  - duplicate detection
- review approval/rejection
- timeline events

## Family Payment
A user can pay for himself and multiple family members using one receipt.
System should create or link payment records for each paidFor member.

## Rental System
Non-members and members can request council rental.
Rental must require admin approval.
Rental payment can be handled like normal payment/transaction.

## Community Features
Future module:
- announcements
- events
- invitations
- member-submitted notices requiring admin approval
- push notifications to council members

## Localization
Do not hardcode UI text long-term.
Plan Arabic and English localization.
Current Arabic text is acceptable during MVP, but future code must prepare for localization.

## Coding Rules
- Do not break existing working login.
- Keep backward compatibility where possible.
- Before major model changes, create backup file.
- Use UTF-8 Arabic text.
- Run flutter analyze after every major change.
- No new package unless necessary.
- Prefer clean architecture and reusable widgets.

## Current Completed
- Firebase connected
- Login works
- Admin dashboard opens
- Member dashboard opens
- Date formatting fixed
- PaymentModel upgraded

## Current Task
Upgrade TransactionModel to support receipt review, OCR fields, family payment, rental support, and audit-ready data.
