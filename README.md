# Blunt Finance

#### Fundraise bluntly in the open with your community

Create permissionless funding rounds with target, hardcap, deadline and a set of pre-defined rules. Based on [Juicebox](https://juicebox.money).

## How it works

[Blunt Finance](https://blunt.finance) allows creating opinionated Juicebox projects with a pre-defined set of rules, by attaching a [BluntDelegate](/contracts/BluntDelegate.sol) data source.

Blunt rounds are created via [BluntDelegateProjectDeployer](/contracts/BluntDelegateProjectDeployer.sol). The deployer guarantees that:

- The `BluntDelegate` data source acts as the project owner until a successful round is closed, preventing any modification by the creator or future project owner;
- Contributors can redeem the amounts contributed in full anytime while the round is in progress or if a round is closed unsuccessfully;
- When a round is closed successfully (ie the fundraising target is reached), ownership is transferred to the rightful owner and a fee is paid to the Blunt Finance treasury in addition to the canonic Juicebox fee. The project owner in exchange receives an amount of BF tokens proportionally to the amount raised.

When a blunt round ends successfully, it turns into a typical Juicebox project that can be managed by the appointed project owner

> Note that it is not yet possible to create a blunt round for existing JB projects, only for new projects.

## Funding Stages

### Fundraise

- Full redemptions
- Token transfers disabled

> Same conditions apply if a round closes without reaching the target.

### Round closed successfully

- Redemptions disabled
- Token transfers enabled
- Data source detached
- Ownership transferred to appointed project owner
- Payments paused
- 1M Token issuance rate
- Unlimited FC duration
- No discount rate
- No delay reconfiguration strategy

## Learn more

- [Blunt Finance Discord](https://discord.gg/Jd8XQjwYZY)
- [Blunt Finance Website](https://blunt.finance)
- [Juicebox protocol](https://juicebox.money)

## Contributing

This project uses [Foundry](https://github.com/foundry-rs/foundry) as development framework.

[Merge to earn](https://mte.slice.so) is used to reward contributors with a piece of the [Blunt Finance slicer](https://slice.so/slicer/24) and its earnings, when pull requests are merged.
