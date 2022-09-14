/// Incentive-associated parameters and data structures.
module econia::incentives {

    // Uses >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin};
    use aptos_std::iterable_table;
    use aptos_std::type_info;
    use std::signer::address_of;
    use std::vector;

    // Uses <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // Test-only uses >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    #[test_only]
    use econia::assets::{Self, QC};

    // Test-only uses <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // Structs >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    /// Portion of taker fees not claimed by an integrator, which are
    /// reserved for Econia.
    struct EconiaFeeStore<phantom QuoteCoinType> has key {
        /// Map from market ID to fees collected for given market,
        /// enabling duplicate checks and interable indexing.
        map: iterable_table::IterableTable<u64, Coin<QuoteCoinType>>
    }

    /// Stores a signing capability for the resource account where
    /// fees, collected by Econia, are stored.
    struct FeeAccountSignerCapabilityStore has key {
        /// Signing capability for fee collection resource account.
        fee_account_signer_capability: SignerCapability
    }

    /// Incentive parameters for assorted operations.
    struct IncentiveParameters has key {
        /// Utility coin type info. Corresponds to the phantom
        /// `CoinType` (`address:module::MyCoin` rather than
        /// `aptos_framework::coin::Coin<address:module::MyCoin>`) of
        /// the coin required for utility purposes. Set to `APT` at
        /// mainnet launch, later the Econia coin.
        utility_coin_type_info: type_info::TypeInfo,
        /// `Coin.value` required to register a market.
        market_registration_fee: u64,
        /// `Coin.value` required to register as a custodian.
        custodian_registration_fee: u64,
        /// Nominal amount divisor for quote coin fee charged to takers.
        /// For example, if a transaction involves a quote coin fill of
        /// 1000000 units and the taker fee divisor is 2000, takers pay
        /// 1/2000th (0.05%) of the nominal amount (500 quote coin
        /// units) in fees. Instituted as a divisor for optimized
        /// calculations.
        taker_fee_divisor: u64,
        /// 0-indexed list from tier number to corresponding parameters.
        integrator_fee_store_tiers: vector<IntegratorFeeStoreTierParameters>
    }

    /// Fee store for a given integrator, on a given market.
    struct IntegratorFeeStore<phantom QuoteCoinType> has store {
        /// Activation tier, incremented by paying utility coins.
        tier: u8,
        /// Collected fees, in quote coins for given market.
        coins: Coin<QuoteCoinType>
    }

    /// All of an integrator's `IntregratorFeeStore`s for given
    /// `QuoteCoinType`.
    struct IntegratorFeeStores<phantom QuoteCoinType> has key {
        /// Map from market ID to `IntegratorFeeStore`, enabling
        /// duplicate checks and iterable indexing.
        map: iterable_table::
            IterableTable<u64, IntegratorFeeStore<QuoteCoinType>>
    }

    /// Integrator fee store tier parameters for a given tier.
    struct IntegratorFeeStoreTierParameters has drop, store {
        /// Nominal amount divisor for taker quote coin fee reserved for
        /// integrators having activated their fee store to the given
        /// tier. For example, if a transaction involves a quote coin
        /// fill of 1000000 units and the fee share divisor at the given
        /// tier is 4000, integrators get 1/4000th (0.025%) of the
        /// nominal amount (250 quote coin units) in fees at the given
        /// tier. Instituted as a divisor for optimized calculations.
        /// May not be larger than the
        /// `IncentiveParameters.taker_fee_divisor`, since the
        /// integrator fee share is deducted from the taker fee (with
        /// the remaining proceeds going to an `EconiaFeeStore` for the
        /// given market).
        fee_share_divisor: u64,
        /// Cumulative cost, in utility coin units, to activate to the
        /// current tier. For example, if an integrator has already
        /// activated to tier 3, which has a tier activation fee of 1000
        /// units, and tier 4 has a tier activation fee of 10000 units,
        /// the integrator only has to pay 9000 units to activate to
        /// tier 4.
        tier_activation_fee: u64,
        /// Cost, in utility coin units, to withdraw from an integrator
        /// fee store. Shall never be nonzero, since a disincentive is
        /// required to prevent excessively-frequent withdrawals and
        /// thus transaction collisions with the matching engine.
        withdrawal_fee: u64
    }

    /// Container for utility coin fees charged by Econia.
    struct UtilityCoinStore<phantom CoinType> has key {
        /// Coins collected as utility fees.
        utility_coins: Coin<CoinType>
    }

    // Structs <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // Error codes >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    /// When caller is not Econia, but should be.
    const E_NOT_ECONIA: u64 = 0;
    /// When type does not correspond to an initialized coin.
    const E_NOT_COIN: u64 = 1;
    /// When passed fee store tiers vector is empty.
    const E_EMPTY_FEE_STORE_TIERS: u64 = 2;
    /// When indicated fee share divisor for given tier is too big.
    const E_FEE_SHARE_DIVISOR_TOO_BIG: u64 = 3;
    /// When the indicated fee share divisor for a given tier is less
    /// than the indicated taker fee divisor.
    const E_FEE_SHARE_DIVISOR_TOO_SMALL: u64 = 4;
    /// When a flat fee is less than the minimum.
    const E_FEE_LESS_THAN_MIN: u64 = 5;
    /// When a fee divisor is less than the minimum.
    const E_DIVISOR_LESS_THAN_MIN: u64 = 6;
    /// When the wrong number of fields are passed for a given tier.
    const E_TIER_FIELDS_WRONG_LENGTH: u64 = 7;
    /// When the indicated tier activation fee is too small.
    const E_ACTIVATION_FEE_TOO_SMALL: u64 = 8;
    /// When the indicated withdrawal fee is too big.
    const E_WITHDRAWAL_FEE_TOO_BIG: u64 = 9;
    /// When the indicated withdrawal fee is too small.
    const E_WITHDRAWAL_FEE_TOO_SMALL: u64 = 10;

    // Error codes <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // Constants >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    /// Index of fee share in vectorized representation of an
    /// `IntegratorFeeStoreTierParameters`.
    const FEE_SHARE_DIVISOR_INDEX: u64 = 0;
    /// `u64` bitmask with all bits set
    const HI_64: u64 = 0xffffffffffffffff;
    /// Minimum possible divisor for avoiding divide-by-zero error.
    const MIN_DIVISOR: u64 = 1;
    /// Minimum possible flat fee, required to disincentivize excessive
    /// bogus transactions.
    const MIN_FEE: u64 = 1;
    /// Number of fields in an `IntegratorFeeStoreTierParameters`
    const N_TIER_FIELDS: u64 = 3;
    /// Index of tier activation fee in vectorized representation of an
    /// `IntegratorFeeStoreTierParameters`.
    const TIER_ACTIVATION_FEE_INDEX: u64 = 1;
    /// Index of withdrawal fee in vectorized representation of an
    /// `IntegratorFeeStoreTierParameters`.
    const WITHDRAWAL_FEE_INDEX: u64 = 2;

    // Constants <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    // Private functions >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    /// Initialize the resource account where fees, collected by Econia,
    /// are stored.
    ///
    /// # Parameters
    /// * `econia`: The Econia account `signer`.
    ///
    /// # Returns
    /// * `signer`: The resource account `signer`.
    ///
    /// # Seed considerations
    /// * Resource account creation seed supplied as an empty vector,
    ///   pending the acceptance of `aptos-core` PR #4173. If PR is not
    ///   accepted by version release, will be updated to accept a seed
    ///   as a function argument.
    ///
    /// # Abort conditions
    /// * If `econia` does not indicate the Econia account.
    fun init_fee_account(
        econia: &signer
    ): signer {
        // Assert signer is from Econia account.
        assert!(address_of(econia) == @econia, E_NOT_ECONIA);
        // Create resource account, storing signing capability.
        let (fee_account, fee_account_signer_capability) = account::
            create_resource_account(econia, b"");
        // Store fee account signer capability under Econia account.
        move_to(econia, FeeAccountSignerCapabilityStore{
            fee_account_signer_capability});
        fee_account // Return fee account signer.
    }

    /// Initialize a `UtilityCoinStore` under the Econia fee account.
    ///
    /// Returns without initializing if a `UtilityCoinStore` already
    /// exists for given `CoinType`.
    ///
    /// # Type Parameters
    /// * `CoinType`: Utility coin phantom type.
    ///
    /// # Parameters
    /// * `fee_account`: Econia fee account `signer`.
    ///
    /// # Abort conditions
    /// * If `CoinType` does not correspond to an initialized
    ///   `aptos_framework::coin::Coin`.
    fun init_utility_coin_store<CoinType>(
        fee_account: &signer
    ) {
        // Assert coin type corresponds to initialized coin.
        assert!(coin::is_coin_initialized<CoinType>(), E_NOT_COIN);
        // If a utility coin store does not already exist at account,
        if(!exists<UtilityCoinStore<CoinType>>(address_of(fee_account)))
            // Initialize one and move it to the account.
            move_to<UtilityCoinStore<CoinType>>(fee_account, UtilityCoinStore{
                utility_coins: coin::zero<CoinType>()});
    }

    /// Set all fields for `IncentiveParameters` under Econia account.
    ///
    /// # Type Parameters
    /// * `UtilityCoinType`: Utility coin phantom type.
    ///
    /// # Parameters
    /// * `econia`: Econia account `signer`.
    /// * `market_registration_fee_ref`: Immutable reference to market
    ///   registration fee to set.
    /// * `custodian_registration_fee_ref`: Immutable reference to
    ///   custodian registration fee to set.
    /// * `taker_fee_divisor_ref`: Immutable reference to
    ///   taker fee divisor to set.
    /// * `integrator_fee_store_tiers_ref`: Immutable reference to
    ///   0-indexed vector of 3-element vectors, with each 3-element
    ///   vector containing fields for a corresponding
    ///   `IntegratorFeeStoreTierParameters`.
    ///
    /// # Abort conditions
    /// * If `econia` is not Econia account.
    /// * If `market_registration_fee_ref` indicates fee that does not
    ///   meet minimum threshold.
    /// * If `custodian_registration_fee_ref` indicates fee that does
    ///   not meet minimum threshold.
    /// * If `taker_fee_divisor_ref` indicates divisor that does not
    ///   meet minimum threshold.
    /// * If `integrator_fee_store_tiers_ref` indicates an empty vector.
    /// * If a indicated inner vector from
    ///   `integrator_fee_store_tiers_ref` is the wrong length.
    /// * If fee share divisor does not decrease with tier number.
    /// * If a fee share divisor is less than taker fee divisor.
    /// * If tier activation fee does not increase with tier number.
    /// * If there is no tier activation fee for the first tier.
    /// * If withdrawal fee does not decrease with tier number.
    /// * If the withdrawal fee for a given tier does not meet minimum
    ///   threshold.
    fun set_incentive_parameters<UtilityCoinType>(
        econia: &signer,
        market_registration_fee_ref: &u64,
        custodian_registration_fee_ref: &u64,
        taker_fee_divisor_ref: &u64,
        integrator_fee_store_tiers_ref: &vector<vector<u64>>
    ) acquires
        FeeAccountSignerCapabilityStore,
        IncentiveParameters
    {
        // Assert signer is from Econia account.
        assert!(address_of(econia) == @econia, E_NOT_ECONIA);
        // Assert market registration fee meets minimum threshold.
        assert!(*market_registration_fee_ref >= MIN_FEE, E_FEE_LESS_THAN_MIN);
        // Assert custodian registration fee meets minimum threshold.
        assert!(*custodian_registration_fee_ref >= MIN_FEE,
            E_FEE_LESS_THAN_MIN);
        // Assert taker fee divisor is meets minimum threshold.
        assert!(*taker_fee_divisor_ref >= MIN_DIVISOR,
            E_DIVISOR_LESS_THAN_MIN);
        // Assert integrator fee store parameters vector not empty.
        assert!(!vector::is_empty(integrator_fee_store_tiers_ref),
            E_EMPTY_FEE_STORE_TIERS);
        // Get fee account signer: if capability store exists,
        let fee_account = if (exists<FeeAccountSignerCapabilityStore>(@econia))
            // Create a signer from the capability within.
            account::create_signer_with_capability(
                &borrow_global<FeeAccountSignerCapabilityStore>(@econia).
                    fee_account_signer_capability) else
            // Otherwise create a signer by initializing fee account.
            init_fee_account(econia);
        // Initialize a utility coin store under the fee acount.
        init_utility_coin_store<UtilityCoinType>(&fee_account);
        // Initialize empty fee store tiers vector.
        let integrator_fee_store_tiers =
            vector::empty<IntegratorFeeStoreTierParameters>();
        // Initialize tracker variables for the fee store parameters of
        // the last accessed tier. Flagged such that activation fee must
        // be nonzero even for the first tier.
        let (divisor_last, activation_fee_last, withdrawal_fee_last) = (
                    HI_64,                   0,               HI_64);
        // Get number of specified integrator fee store tiers.
        let n_tiers = vector::length(integrator_fee_store_tiers_ref);
        let i = 0; // Declare counter for loop variable.
        while (i < n_tiers) { // Loop over all specified tiers
            // Borrow immutable reference to fields for given tier.
            let tier_fields_ref =
                vector::borrow(integrator_fee_store_tiers_ref, i);
            // Assert containing vector is correct length.
            assert!(vector::length(tier_fields_ref) == N_TIER_FIELDS,
                E_TIER_FIELDS_WRONG_LENGTH);
            // Borrow immutable reference to fee share divisor.
            let fee_share_divisor_ref =
                vector::borrow(tier_fields_ref, FEE_SHARE_DIVISOR_INDEX);
            // Assert indicated fee share divisor is less than divisor
            // from last tier.
            assert!(*fee_share_divisor_ref < divisor_last,
                E_FEE_SHARE_DIVISOR_TOO_BIG);
            // Assert indicated fee share divisor is greater than or
            // equal to taker fee divisor.
            assert!(*fee_share_divisor_ref >= *taker_fee_divisor_ref,
                E_FEE_SHARE_DIVISOR_TOO_SMALL);
            // Borrow immutable reference to tier activation fee.
            let tier_activation_fee_ref =
                vector::borrow(tier_fields_ref, TIER_ACTIVATION_FEE_INDEX);
            // Assert activation fee is greater than that of last tier.
            assert!(*tier_activation_fee_ref > activation_fee_last,
                E_ACTIVATION_FEE_TOO_SMALL);
            // Borrow immutable reference to withdrawal fee.
            let withdrawal_fee_ref =
                vector::borrow(tier_fields_ref, WITHDRAWAL_FEE_INDEX);
            // Assert withdrawal fee is less than that of last tier.
            assert!(*withdrawal_fee_ref < withdrawal_fee_last,
                E_WITHDRAWAL_FEE_TOO_BIG);
            // Assert withdrawal fee is above minimum threshold.
            assert!(*withdrawal_fee_ref > MIN_FEE, E_WITHDRAWAL_FEE_TOO_SMALL);
            // Mark indicated tier in ongoing vector of tiers.
            vector::push_back(&mut integrator_fee_store_tiers,
                IntegratorFeeStoreTierParameters{
                    fee_share_divisor: *fee_share_divisor_ref,
                    tier_activation_fee: *tier_activation_fee_ref,
                    withdrawal_fee: *withdrawal_fee_ref});
            // Store divisor for comparison during next iteration.
            divisor_last = *fee_share_divisor_ref;
            // Store activation fee to compare during next iteration.
            activation_fee_last = *tier_activation_fee_ref;
            // Store withdrawal fee to compare during next iteration.
            withdrawal_fee_last = *withdrawal_fee_ref;
            i = i + 1; // Increment loop counter
        };
        // If incentive parameters resource already at Econia account:
        if (exists<IncentiveParameters>(@econia)) {
            // Borrow a mutable reference to it.
            let incentive_parameters =
                borrow_global_mut<IncentiveParameters>(@econia);
            // Update its fields accordingly.
            incentive_parameters.utility_coin_type_info =
                type_info::type_of<UtilityCoinType>();
            incentive_parameters.market_registration_fee =
                *market_registration_fee_ref;
            incentive_parameters.custodian_registration_fee =
                *custodian_registration_fee_ref;
            incentive_parameters.taker_fee_divisor =
                *taker_fee_divisor_ref;
            incentive_parameters.integrator_fee_store_tiers =
                integrator_fee_store_tiers;
        } else { // If resource not at Econia account:
            // Move one to it with given values
            move_to<IncentiveParameters>(econia, IncentiveParameters{
                utility_coin_type_info: type_info::type_of<UtilityCoinType>(),
                market_registration_fee: *market_registration_fee_ref,
                custodian_registration_fee: *custodian_registration_fee_ref,
                taker_fee_divisor: *taker_fee_divisor_ref,
                integrator_fee_store_tiers});
        }
    }

    // Tests >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

    #[test(account = @user)]
    #[expected_failure(abort_code = 0)]
    /// Verify failure for non-Econia caller.
    fun test_init_fee_account_not_econia(
        account: &signer
    ) {
        init_fee_account(account); // Attempt invalid invocation.
    }

    #[test(account = @user)]
    #[expected_failure(abort_code = 1)]
    /// Verify failure for attempting to initialize with non-coin type.
    fun test_init_utility_coin_store_not_coin(
        account: &signer
    ) {
        // Attempt invalid invocation.
        init_utility_coin_store<IncentiveParameters>(account);
    }

    #[test(econia = @econia)]
    /// Verify successful `UtilityCoinStore` initialization.
    fun test_init_utility_coin_store(
        econia: &signer
    ) {
        assets::init_coin_types(econia); // Init coin types.
        let fee_account = init_fee_account(econia); // Init fee account.
        // Init utility coin store under fee account.
        init_utility_coin_store<QC>(&fee_account);
        // Verify can call re-init for when already initialized.
        init_utility_coin_store<QC>(&fee_account);
        // Assert a utility coin store exists under fee account.
        assert!(exists<UtilityCoinStore<QC>>(address_of(&fee_account)), 0);
    }

    // Tests <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

}