# cliamp ios

The iOS client is not implemented yet. The [iOS parity plan and progress
tracker](../docs/ios-parity.md) defines the Android baseline, phased work,
acceptance criteria, and remaining platform decisions. Start there when
implementing or reviewing the port, and update its task IDs as work lands.

Two things worth reading before anything lands here:
[`../docs/design.md`](../docs/design.md), which is the design system the Android
client already implements and the thing that keeps the clients recognisably one
app, and [`../android/README.md`](../android/README.md) for the decisions that
turned out to matter — the declarative provider spec, resolving stream URLs at
play time rather than storing them, and keeping credentials out of plain files.
