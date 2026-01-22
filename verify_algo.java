
public class verify_algo {
    public static void main(String[] args) {
       long seed = 666649373L;
       System.out.println("Java Results for seed: " + seed);
       
       // Case 0: Sunshine
       long res0 = getPassWord2(seed, "SUNSHINE");
       System.out.println("SUNSHINE (0): " + res0);
       
       // Case 1: Sunshine Masked
       long res1 = res0 & 0xFFFFFFFFL;
       System.out.println("SUNSHINE Masked (1): " + res1);
    }
    
    public static long getPassWord2(long challenge, String agentClassName) {
        if (agentClassName.contains("SUNSHINE")) {
             return (((challenge + 309809441) ^ 287852129) - 556077345) ^ -2011081661;
        }
        return 0;
    }
}
