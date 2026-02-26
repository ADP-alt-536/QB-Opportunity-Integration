// QB_Service.cls
// Adding testable configuration injection support and a static method for test mocking

public class QB_Service {
    private static Map<String, String> config;

    public static void initializeConfiguration(Map<String, String> productionConfig) {
        config = productionConfig;
    }

    public static void setTestConfiguration(Map<String, String> testConfig) {
        config = testConfig;
    }

    public static Map<String, String> getConfiguration() {
        return config;
    }

    // Method to mock configuration for testing
    public static void mockConfig(String key, String value) {
        if (config == null) {
            config = new Map<String, String>();
        }
        config.put(key, value);
    }

    // Sample method using the configuration
    public static void performAction() {
        // Example usage of config
        if (config != null && config.containsKey('someKey')) {
            // Do something based on the configuration
        } else {
            // Handle the absence of configuration
        }
    }
}