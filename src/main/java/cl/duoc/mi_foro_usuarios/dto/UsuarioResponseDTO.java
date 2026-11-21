package cl.duoc.mi_foro_usuarios.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data 
@NoArgsConstructor 
@AllArgsConstructor 
@Builder 
public class UsuarioResponseDTO {

    private Long id;
    private String usuario;
    // private String password;
    private String nombre;
    private String correo;
    private Long tu_id;
    private Integer activo;

}
