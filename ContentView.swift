import SwiftUI
import CoreBluetooth

//Connects to the Low Energy Bluetooth Module on the circuit
class BluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, ObservableObject {
    //declaring variables
    var centralManager: CBCentralManager!
    var discoveredPeripheral: CBPeripheral?
    var hm10ServiceUUID = CBUUID(string: "FFE0")
    var hm10CharacteristicUUID = CBUUID(string: "FFE1")

    @Published var isConnected = false
    @Published var receivedMessage = ""

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    //Scans for the HM-10 connected to arduino
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: [hm10ServiceUUID], options: nil)
            print("Scanning for HM-10 devices...")
        } else {
            print("Bluetooth is not available.")
        }
    }
    
    //Connects to the Module
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("Discovered \(peripheral.name ?? "Unknown")")
        discoveredPeripheral = peripheral
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }

    //Prints when its connected
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "Unknown")")
        isConnected = true
        peripheral.delegate = self
        peripheral.discoverServices([hm10ServiceUUID])
    }

    //Prints services
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            for service in services {
                print("Discovered service: \(service.uuid)")
                peripheral.discoverCharacteristics([hm10CharacteristicUUID], for: service)
            }
        }
    }

    //Prints characteristics
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                print("Discovered characteristic: \(characteristic.uuid)")
            }
        }
    }

    //Function to send messages to arduino
    func sendMessage(_ message: String) {
        guard let peripheral = discoveredPeripheral else { return }
        if let characteristic = peripheral.services?.first?.characteristics?.first(where: { $0.uuid == hm10CharacteristicUUID }) {
            let dataToSend = message.data(using: .utf8)
            peripheral.writeValue(dataToSend!, for: characteristic, type: .withResponse)
            print("Sent: \(message)")
        }
    }
}

//Formats/declares current weather
struct WeatherData: Codable {
    let current: CurrentWeather
}

//Formats/declares the variables of weather
struct CurrentWeather: Codable {
    let temp_f: Double
    let humidity: Int
    let condition: Condition
}

//Formats/declares weather condition
struct Condition: Codable {
    let text: String
}

//Formats what the app looks like/functions
struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @State private var weatherInfo: [String] = []
    @State private var timer: Timer? = nil
    @State private var location: String = ""
    
    //Main layout of app
    var body: some View {
        ZStack{
            Color.black
                .ignoresSafeArea()
            VStack{
                    (Text(Image(systemName: "cloud")) + Text("Bluetooth Weather Module"))
                        .font(.system(.largeTitle, design: .serif))
                        .multilineTextAlignment(TextAlignment .center)
                        .padding()
                        .foregroundColor(.white)
                if bluetoothManager.isConnected {
                    HStack{
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("Connected to HM-10")
                            .font(.headline)
                            .foregroundColor(.green)
                    }
                }
                else {
                    HStack{
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.red)
                        Text("Not connected")
                            .font(.headline)
                            .foregroundColor(.red)
                    }
                }
                Spacer().frame(height: 30)
                
                //Text Field for location of the biker
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.black)
                        
                        ZStack(alignment: .leading) {
                            if location.isEmpty {
                                Text("Location")
                                    .foregroundColor(.black)
                            }
                            TextField("", text: $location)
                                .foregroundColor(.black)
                            }
                    }
                    .padding()
                    .font(.title)
                    .background(Capsule().fill(Color.white))
                
                Spacer().frame(height: 20)
                Button("Send to Weather Module") {fetchWeatherData()}
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                
                Image(.chart)
                    .resizable()
                    .frame(width: 400, height: 400)
            }
            .padding()
            
        }
        .onAppear {
            //Start the timer when the view appears
            startTimer()
        }
        .onDisappear {
            //Invalidate the timer when the view disappears
            timer?.invalidate()
        }
    }
    
    //Starts and runs 15min timer to update weather info
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            fetchWeatherData()
        }
    }
    
    //Uses API data to get current weather info
    func fetchWeatherData() {
        let apiKey = "8860483f833645fb86820008240511" //WeatherAPI.com key
        let urlString = "https://api.weatherapi.com/v1/current.json?key=\(apiKey)&q=\(location)" //Api call

        guard let url = URL(string: urlString) else { return }

        //Decodes data or error
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching weather data: \(error)")
                return
            }

            guard let data = data else {
                print("No data received")
                return
            }

            //Reads the API data recieved
            do {
                //Decode the weather data
                let weatherData = try JSONDecoder().decode(WeatherData.self, from: data)
                print(weatherData)
                let temperature = weatherData.current.temp_f
                let humidity = weatherData.current.humidity
                let conditionRank = weatherConditionRank(conditionText: weatherData.current.condition.text)
                
                //Store numerical data only
                self.weatherInfo = [
                    "\(temperature)",      //Temperature in °F
                    "\(humidity)",         //Humidity percentage
                    "\(conditionRank),"     //Condition rank from 0 to 10
                ]
                print("Weather Data: \(self.weatherInfo)")
                
                //Automatically sends weather data
                sendWeatherData()
            } catch {
                print("Error decoding JSON: \(error)")
            }
        }
        task.resume()
    }

    //Creates a ranking for condition (0-10)
    func weatherConditionRank(conditionText: String) -> Int {
        switch conditionText.lowercased() {
        case "clear":
            return 0
        case "partly cloudy":
            return 2
        case "cloudy":
            return 4
        case "overcast":
            return 5
        case "rain":
            return 6
        case "thunderstorm":
            return 8
        case "snow":
            return 9
        case "tornado", "hurricane":
            return 10
        default:
            return 5 //Default rank for unknown conditions
        }
    }
    
    //Sends data to the arduino in a string array
    func sendWeatherData() {
        //Send only numerical values
        let message = weatherInfo.joined(separator: ",")
        bluetoothManager.sendMessage(message)
    }
}

//Main for xcode formating reasons
@main
struct BluetoothWeatherApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
