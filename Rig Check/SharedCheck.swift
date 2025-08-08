import Foundation
import SwiftUI
import CloudKit

// MARK: - SharedCheck (ephemeral collaboration record stored in CloudKit)

struct SharedCheck: Codable, Equatable {
    var formId: String
    var submissionId: String
    var unit: String
    var moduleStatus: [CheckModule: ModuleStatus]
    var activeModule: CheckModule?      // optional soft-lock/presence
    var activeBy: String?               // device/crew indicator
    var updatedAt: Date

    // Compact dictionary form for storage (String keys/values)
    var moduleStatusRaw: [String: String] {
        moduleStatus.mapKeys(\.rawValue).mapValues(\.rawValue)
    }
}

private extension Dictionary {
    func mapKeys<T>(_ transform: (Key) -> T) -> [T: Value] where T: Hashable {
        var out: [T: Value] = [:]
        for (k, v) in self { out[transform(k)] = v }
        return out
    }
}

// MARK: - Answer Models You Already Had

struct AEDAnswers: Codable {
    var scannedCode: String
    var adultQty: Int
    var pedQty: Int
    var adultExpiry: Date?
    var pedExpiry: Date?
    var batteryBars: Int?
    var vtachPass: Bool?
    var nsrPass: Bool?
    var motionPass: Bool?
    var razorPresent: Bool
}

struct StretcherAnswers: Codable {
    var scannedCode: String?
    var stretcherMissing: Bool
    var missingPhotoJPEG: Data?
    var fourSeasonWrapPresent: Bool?
    var softRestraintsPresent: Bool?
    var fivePointPresent: Bool?
    var autoLoadBatteryPresentCharged: Bool?
    var autoLoadFunctional: Bool?
    var autoLoadIssuePhotoJPEG: Data?
    var autoLoadIssueComment: String?
    var firstInBagsSecured: Bool?
}

struct StairChairAnswers: Codable {
    var scannedCode: String?
    var chairMissing: Bool
    var missingPhotoJPEG: Data?
    var twoShoulderStraps: Bool?
    var oneAnkleStrap: Bool?
    var treadsGood: Bool?
    var mechanismsGood: Bool?
    var defectPhotoJPEG: Data?
    var defectComment: String?
}

struct AirwayBagAnswers: Codable {
    var scannedCode: String?
    var bagMissing: Bool
    var missingPhotoJPEG: Data?

    // Q1
    var majorDamage: Bool?
    var damagePhotoJPEG: Data?

    // Q2
    var oxygenLevel: String?      // "FULL", "3/4", "HALF", "1/4", "EMPTY"
    var oxygenExpiry: Date?

    // Q3
    var regulatorPresent: Bool?

    // Q4–22 (quantities + expirations)
    var qtyMasksSurgical: Int
    var qtyTraumaShears: Int
    var qtyAdultNRB: Int;     var expAdultNRB: Date?
    var qtyAdultNC: Int;      var expAdultNC: Date?
    var qtyPedNRB: Int;       var expPedNRB: Date?
    var qtyPedNC: Int;        var expPedNC: Date?
    var qtyO2Tubing: Int;     var expO2Tubing: Date?
    var qtyAdultBVM: Int;     var expAdultBVM: Date?
    var qtyPedBVMMask: Int

    var opaPresent: Bool?
    var npaPresent: Bool?;    var expNPA: Date?

    var qtySurgiLube: Int;    var expSurgiLube: Date?
    var qtySoftSuction: Int;  var expSoftSuction: Date?

    var biteStickPresent: Bool?

    var chestSealPresent: Bool?; var expChestSeal: Date?
    var infantBVMPresent: Bool?; var expInfantBVM: Date?

    var qtyAdultNeb: Int;     var expAdultNeb: Date?
    var qtyPedNeb: Int;       var expPedNeb: Date?

    var albuterolPresent: Bool?; var expAlbuterol: Date?
}

// MARK: - Portable Suction

extension SessionData {
    struct PortableSuctionAnswers: Codable {
        var deviceCode: String?
        var deviceMissing: Bool
        var missingPhotoJPEG: Data?

        var cleanCanisterAttached: Bool?
        var hardSuctionPresent: Bool?
        var hardSuctionExpiry: Date?

        var operatesOnBattery: Bool?
        // MP4 payload (already compressed < 50MB)
        var batteryProofVideoMP4: Data?
    }
}

// MARK: - Exterior Cabinets

extension SessionData {
    struct ExteriorCabinetsAnswers: Codable {
        // O2 (same labels as O2 chips in CheckUI)
        var mainO2Level1: String?          // "FULL","3/4","HALF","1/4","EMPTY"
        var mainO2Level2: String?          // optional; allow skipping second
        var skipSecondMainO2: Bool
        var mainO2Expiry1: Date?
        var mainO2Expiry2: Date?

        // Scanned items (prefix check only)
        var reevesCode: String?            // "RV..."
        var scoopCode: String?             // "SCP..."
        var pediBoardCode: String?         // "PB..."
        var tractionSplintCode: String?    // "TS..."

        // Presence toggles
        var boardSplintsPresent: Bool?
        var binderLiftPresent: Bool?
        var jumperCablesPresent: Bool?
        var rescueRopeBagPresent: Bool?
        var cCollarBagsPresent: Bool?

        // Count fields
        var pfdQty: Int
        var rescueHelmetsQty: Int
        var rescueGlovesQty: Int
        var rescueJacketsQty: Int

        // Saturday-only detail fields
        var boardSmallQty: Int
        var boardMediumQty: Int
        var boardLargeQty: Int

        var binderStrapsGood: Bool?
        var binderBucklesGood: Bool?

        var helmetsConditionGood: Bool?

        var reevesStrapsGood: Bool?
        var reevesBucklesGood: Bool?
        var reevesMaterialDamage: Bool?
        var reevesDamagePhotoJPEG: Data?

        var scoopMechanicalGood: Bool?
        var scoopLocksGood: Bool?
    }
}

// MARK: - Hub modules

enum CheckModule: String, CaseIterable, Codable, Hashable {
    case aed = "AED"
    case stretcher = "Stretcher"
    case stairChair = "Stair Chair"
    case airwayBag = "Airway Bag"
    case traumaBag = "Trauma Bag"
    case communications = "Communications"
    case lucas = "LUCAS"
    case portableSuction = "Portable Suction"
    case interiorCompartments = "Interior Compartments"
    case exteriorCompartments = "Exterior Compartments"  // ← keep this spelling app-wide
}

// MARK: - Hub status

enum ModuleStatus: String, Codable {
    case notStarted, inProgress, completed
}

// MARK: - Trauma Bag

struct TraumaBagAnswers: Codable {
    enum CalSolutionStatus: String, Codable {
        case bothPresent = "Both Present"
        case greenMissing = "Green Missing"
        case blueMissing  = "Blue Missing"
    }

    // Bag
    var bagCode: String?
    var bagMissing: Bool
    var missingPhotoJPEG: Data?

    // Medication kit
    var medKitCode: String?
    var qtyAlbuterol: Int;        var expAlbuterol: Date?
    var qtyAdultEpi: Int;         var expAdultEpi: Date?
    var qtyPedEpi: Int;           var expPedEpi: Date?
    var qtyNaloxone: Int;         var expNaloxone: Date?
    var qtyOralGlucose: Int;      var expOralGlucose: Date?
    var qtyAspirinBottle: Int;    var expAspirin: Date?
    var qtyBeeStingSwab: Int?     // normalize: optional if box count varies
    var expBeeStingSwab: Date?
    var biteStickPresent: Bool?
    var sharpsShuttlePresent: Bool?

    // Pulse Ox
    var pulseOxCode: String?
    var pulseOxMissing: Bool
    var pulseOxMissingPhotoJPEG: Data?

    // Glucometer
    var glucometerCode: String?
    var glucometerMissing: Bool
    var glucometerMissingPhotoJPEG: Data?

    // Glucometer sub-questions
    var calSolutionStatus: CalSolutionStatus
    var blueCalReading: String
    var greenCalReading: String
    var expBlueCalSolution: Date?
    var expGreenCalSolution: Date?
    var lancetsPresent: Bool?
    var bandagesPresent: Bool?
    var qtyTestStrips: Int

    // Bag contents
    var traumaShearsPresent: Bool?
    var cCollarPresent: Bool?
    var qtyTraumaDressing: Int
    var qtyConvenienceBags: Int
    var qtyFaceShield: Int
    var qtyColdPacks: Int;        var expColdPacks: Date?
    var penLightPresent: Bool?
    var qtyBloodStopper: Int
    var qtySafetyGlasses: Int
    var qtyPetroleumGauze: Int;   var expPetroleumGauze: Date?
    var qtyAdhesiveBandages: Int; var expAdhesiveBandages: Date?
    var qty5x9: Int
    var qty4x4: Int
    var qtyRolledGauze: Int
    var sterileWaterPresent: Bool?; var expSterileWater: Date?
    var qtyTape: Int
    var stethoscopePresent: Bool?
    var largeAdultBPCuffPresent: Bool?
    var childBPCuffPresent: Bool?
    var infantBPCuffPresent: Bool?
    var handheldSuctionPresent: Bool?
    var qtyTourniquet: Int
    var qtyCravats: Int
    var qtyRedBioBags: Int
}

// MARK: - Communications model nested in SessionData

extension SessionData {
    struct CommunicationsAnswers: Codable {
        var cadCode: String?
        var vhfCode: String?
        var ipadCode: String?
        var ipadMissing: Bool
        var ipadIsCADDevice: Bool
        var comments: String?

        // Optional taps
        var cadOnline: Bool? = nil
        var vpnIssue: Bool? = nil
        var internetIssue: Bool? = nil
        var crewLoggedIntoCAD: Bool? = nil
        var mobileRadioFunctional: Bool? = nil

        init(
            cadCode: String?,
            vhfCode: String?,
            ipadCode: String?,
            ipadMissing: Bool,
            ipadIsCADDevice: Bool,
            comments: String?
        ) {
            self.cadCode = cadCode
            self.vhfCode = vhfCode
            self.ipadCode = ipadCode
            self.ipadMissing = ipadMissing
            self.ipadIsCADDevice = ipadIsCADDevice
            self.comments = comments
        }
    }
}

// MARK: - Lucas model nested in SessionData

extension SessionData {
    struct LucasAnswers: Codable {
        // Device
        var deviceCode: String? = nil
        var deviceMissing: Bool = false
        var missingPhotoJPEG: Data? = nil

        // Gear
        var suctionCupPresent: Bool? = nil
        var spareSuctionCupPresent: Bool? = nil

        // Primary battery (same choices as oxygen level)
        var primaryBatteryLevel: String? = nil   // "FULL","3/4","HALF","1/4","EMPTY"
        var primaryBatteryExpiry: Date? = nil

        // Spare battery
        var spareBatteryPresent: Bool? = nil
        var spareBatteryLevel: String? = nil     // same choices as above
        var spareBatteryExpiry: Date? = nil

        // Hardware
        var backPlatePresent: Bool? = nil
        var neckStrapPresent: Bool? = nil

        // Weekly tests (Wednesday only)
        var weeklyTest1Pass: Bool? = nil
        var weeklyTest2Pass: Bool? = nil
    }
}

// MARK: - SessionData (Observable)

final class SessionData: ObservableObject {
    // Welcome selections
    @Published var crew1: String = ""
    @Published var crew2: String = ""
    @Published var crew3: String = ""
    @Published var unit:  String = ""

    // Expected QR codes pulled from the vehicle record
    @Published var expectedAEDCode: String = ""        // QID 15
    @Published var expectedStretcherCode: String = ""  // QID 17
    @Published var expectedStairChairCode: String = "" // QID 18
    @Published var expectedAirwayCode: String = ""     // QID 20

    // Used by Communications & Trauma Bag & Lucas
    @Published var expectedCADCode: String = ""        // QID 19
    @Published var expectedIPadCode: String = ""       // QID 22
    @Published var expectedVHFCode: String = ""        // label-only or QID 21
    @Published var expectedTraumaBagCode: String = ""  // QID 23
    @Published var expectedLucasCode: String = ""      // QID 16
    @Published var expectedPortableSuctionCode: String = "" // QID 23

    @Published var selectedStation: Station? = nil

    // MARK: - Collaboration / CloudKit state

    @Published var formId: String = ""                 // set after VehicleCheckWizard
    @Published var submissionId: String = ""           // set after VehicleCheckWizard
    @Published var showCollabSheet: Bool = false       // UI: show QR sheet in Hub

    // simple stable device id (for presence)
    private let deviceId: String = {
        let k = "gcems.device.id"
        if let v = UserDefaults.standard.string(forKey: k) { return v }
        let v = UUID().uuidString
        UserDefaults.standard.set(v, forKey: k)
        return v
    }()

    // CloudKit sync service (provided in CKSyncService.swift)
    private let sync = CKSyncService.shared

    // Module status map
    @Published var moduleStatus: [CheckModule: ModuleStatus] = [
        .aed: .notStarted,
        .stretcher: .notStarted,
        .stairChair: .notStarted,
        .airwayBag: .notStarted,
        .traumaBag: .notStarted,
        .communications: .notStarted,
        .lucas: .notStarted,
        .portableSuction: .notStarted,
        .interiorCompartments: .notStarted,
        .exteriorCompartments: .notStarted     // keep key consistent with enum
    ]

    // MARK: - Progress helpers (broadcast + draft persistence wired in)

    func start(_ m: CheckModule) {
        if moduleStatus[m] != .completed { moduleStatus[m] = .inProgress }
        broadcast(activeModule: m)
        persistDraftHeader()
    }

    func complete(_ m: CheckModule) {
        moduleStatus[m] = .completed
        broadcast(activeModule: nil)
        persistDraftHeader()
        checkForCompletionCleanup()
    }

    func reset(_ m: CheckModule) {
        moduleStatus[m] = .notStarted
        broadcast(activeModule: nil)
        persistDraftHeader()
    }

    // Answers cached for final POST (auto-mark module completed on save)
    @Published var aedAnswers: AEDAnswers? {
        didSet { if aedAnswers != nil { markCompleted(.aed) } }
    }
    @Published var stretcherAnswers: StretcherAnswers? {
        didSet { if stretcherAnswers != nil { markCompleted(.stretcher) } }
    }
    @Published var stairChairAnswers: StairChairAnswers? {
        didSet { if stairChairAnswers != nil { markCompleted(.stairChair) } }
    }
    @Published var airwayBagAnswers: AirwayBagAnswers? {
        didSet { if airwayBagAnswers != nil { markCompleted(.airwayBag) } }
    }
    @Published var communicationsAnswers: SessionData.CommunicationsAnswers? {
        didSet { if communicationsAnswers != nil { markCompleted(.communications) } }
    }
    @Published var traumaBagAnswers: TraumaBagAnswers? {
        didSet { if traumaBagAnswers != nil { markCompleted(.traumaBag) } }
    }
    @Published var lucasAnswers: SessionData.LucasAnswers? {
        didSet { if lucasAnswers != nil { markCompleted(.lucas) } }
    }
    @Published var portableSuctionAnswers: SessionData.PortableSuctionAnswers? {
        didSet { if portableSuctionAnswers != nil { markCompleted(.portableSuction) } }
    }

    // NEW: Exterior Cabinets answers live inside the class (not in an extension)
    @Published var exteriorCabinetsAnswers: SessionData.ExteriorCabinetsAnswers? {
        didSet { if exteriorCabinetsAnswers != nil { markCompleted(.exteriorCompartments) } }
    }

    // Welcome “Continue” enabled?
    var isSetupComplete: Bool {
        (!crew1.isEmpty || !crew2.isEmpty || !crew3.isEmpty) && !unit.isEmpty
    }

    // MARK: - NEW for Restock: lightweight storage used by RestockBuilder

    /// Present/Missing style items (true == present, false == missing)
    @Published var restockBools: [String: Bool] = [:]

    /// Quantity items (current on-hand count)
    @Published var restockInts: [String: Int] = [:]

    // Simple accessors used by RestockBuilder
    func boolFor(_ key: String) -> Bool? {
        restockBools[key]
    }
    func setBool(_ v: Bool, for key: String) {
        restockBools[key] = v
    }
    func intFor(_ key: String) -> Int {
        restockInts[key] ?? 0
    }
    func setInt(_ v: Int, for key: String) {
        restockInts[key] = v
    }

    // MARK: - Calendar helpers

    var isSaturday: Bool {
        Calendar.current.component(.weekday, from: Date()) == 7
    }
    var isFirstOfMonth: Bool {
        Calendar.current.component(.day, from: Date()) == 1
    }

    // MARK: - Hub helpers

    /// True when all modules are marked .completed
    var allModulesComplete: Bool {
        for m in CheckModule.allCases {
            if moduleStatus[m] != .completed { return false }
        }
        return true
    }

    /// Draft flag for launch "Resume Draft" button
    var hasActiveDraft: Bool {
        guard !submissionId.isEmpty else { return false }
        return !allModulesComplete
    }

    /// Temporary shim so the placeholder tiles in CheckHubView don’t crash.
    /// We’ll swap this to your real flags later if you prefer.
    func value(forKey key: String) -> Any? {
        switch key {
        case "exterior":
            return moduleStatus[ .exteriorCompartments ] == .completed
        case "interiorCab":
            return moduleStatus[ .airwayBag ] == .completed
        case "interiorCompartments":
            return moduleStatus[ .interiorCompartments ] == .completed
        case "oxygen":
            return moduleStatus[ .portableSuction ] == .completed
        case "lifepak":
            return moduleStatus[ .lucas ] == .completed
        case "meds":
            return moduleStatus[ .traumaBag ] == .completed
        default:
            return nil
        }
    }

    // MARK: - Collaboration lifecycle

    /// Call once after VehicleCheckWizard creates the Jotform submission.
    func beginCollaboration(formId: String, submissionId: String) {
        self.formId = formId
        self.submissionId = submissionId
        persistDraftHeader()
        broadcast(activeModule: nil) // upsert CK record initially

        // Start watching for remote changes (simple polling MVP; upgrade to CK subscriptions later)
        sync.watch(submissionId: submissionId) { [weak self] remote in
            guard let self else { return }
            DispatchQueue.main.async {
                // Merge remote statuses (last-write-wins per module)
                for (key, raw) in remote.moduleStatusRaw {
                    if let m = CheckModule(rawValue: key),
                       let st = ModuleStatus(rawValue: raw),
                       self.moduleStatus[m] != st {
                        self.moduleStatus[m] = st
                    }
                }
                self.objectWillChange.send()
            }
        }
    }

    // MARK: - Internal helpers

    private func markCompleted(_ module: CheckModule) {
        moduleStatus[module] = .completed
        broadcast(activeModule: nil)
        persistDraftHeader()
        checkForCompletionCleanup()
    }

    /// Broadcast current state to CloudKit
    private func broadcast(activeModule: CheckModule?) {
        guard !submissionId.isEmpty, !formId.isEmpty else { return }
        let payload = SharedCheck(
            formId: formId,
            submissionId: submissionId,
            unit: unit,
            moduleStatus: moduleStatus,
            activeModule: activeModule,
            activeBy: deviceId,
            updatedAt: Date()
        )
        Task { try? await sync.upsert(payload) }
    }

    /// Persist the lightweight header for Resume Draft
    private func persistDraftHeader() {
        let header = DraftHeader(
            submissionId: submissionId,
            formId: formId,
            unit: unit,
            createdAt: DraftManager.shared.current?.createdAt ?? Date(),
            lastUpdatedAt: Date(),
            moduleStatus: moduleStatus
        )
        DraftManager.shared.save(header)
        NotificationCenter.default.post(name: .gcemsDraftDidChange, object: nil)
    }

    /// If everything is done, clean up CloudKit + local draft
    private func checkForCompletionCleanup() {
        guard allModulesComplete else { return }
        Task {
            try? await sync.delete(submissionId: submissionId) // ephemeral record
            DraftManager.shared.clear()                        // hide Resume Draft
        }
    }
}