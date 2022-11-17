# Blunt Finance

#### Fundraise bluntly in the open with your community.

Allocate a portion of reserved tokens of a JB project and send arbitrary payments to contributors of a previous funding cycle. Based on the use of [slicers](https://slice.so).

## How it works

[Blunt Finance](https://blunt.finance) allows creating a [Juicebox](https://juicebox.money) project with a pre-defined set of rules, via the [BluntDelegate](/contracts/BluntDelegate.sol) data source.

Blunt rounds are created via [BluntDelegateProjectDeployer](/contracts/BluntDelegateProjectDeployer.sol). The deployer guarantees that:

- The `BluntDelegate` data source acts the project owner until a successful blunt round is closed, preventing any modification by the creator or future project owner;
- During the blunt round, full redemptions are enabled and Token transfers are disabled;
- In case the specified target is reached, a slicer contract is created and round participants can withdraw an amount of slices proportional to their contribution.

When a blunt round ends successfully, it turns into a typical Juicebox project with the new slicer in the reserved rate, according to the parameters specified during the blunt round.

The slicer receives reserved rate tokens from future founding cycles and distributes it to round participants. It's also able to split any payment sent to it, as long as the currency is accepted.

> Note that it is not yet possible to create a blunt round for existing JB projects, only for new projects.

## Learn more

- [Slice protocol](https://slice.so)
- [Juicebox protocol](https://juicebox.money)

## Contributing

This project uses [Foundry](https://github.com/foundry-rs/foundry) as development framework.

[Merge to earn](https://mte.slice.so) is used to reward contributors with a piece of the [Blunt Finance slicer](https://slice.so/slicer/24) and its earnings, when pull requests are merged.
